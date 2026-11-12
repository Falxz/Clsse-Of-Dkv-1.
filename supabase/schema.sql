-- CLASS SEAT SPINNER — Supabase schema
-- Run in Supabase SQL Editor as project owner.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text not null default 'User',
  role text not null default 'user' check (role in ('user','admin','developer')),
  created_at timestamptz not null default now()
);
create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);
create unique index if not exists students_name_unique_lower on public.students (lower(name));
create table if not exists public.spin_history (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null unique references public.students(id) on delete cascade,
  student_name text not null,
  spin_no integer not null unique check (spin_no between 1 and 42),
  created_at timestamptz not null default now()
);
create table if not exists public.classroom_state (
  id integer primary key default 1 check (id=1),
  updated_at timestamptz not null default now()
);
insert into public.classroom_state(id) values(1) on conflict do nothing;

create or replace function public.current_app_role()
returns text language sql stable security definer set search_path=public
as $$ select role from public.profiles where id=auth.uid() $$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
 insert into public.profiles(id,email,display_name,role)
 values(new.id,new.email,coalesce(new.raw_user_meta_data->>'display_name','User'),'user')
 on conflict(id) do nothing;
 return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.students enable row level security;
alter table public.spin_history enable row level security;
alter table public.classroom_state enable row level security;


drop policy if exists "authenticated can read profiles" on public.profiles;

drop policy if exists "users read own profile; staff read profiles" on public.profiles;

create policy "users read own profile; staff read profiles"
on public.profiles
for select
to authenticated
using (
  id = auth.uid()
  or public.current_app_role() in ('admin','developer')
);

drop policy if exists "users read students" on public.students;
create policy "users read students" on public.students for select to authenticated using (true);
drop policy if exists "admins manage students" on public.students;
create policy "admins manage students" on public.students for all to authenticated using (public.current_app_role() in ('admin','developer')) with check (public.current_app_role() in ('admin','developer'));
drop policy if exists "users read history" on public.spin_history;
create policy "users read history" on public.spin_history for select to authenticated using (true);
drop policy if exists "admins manage history" on public.spin_history;
create policy "admins manage history" on public.spin_history for all to authenticated using (public.current_app_role() in ('admin','developer')) with check (public.current_app_role() in ('admin','developer'));
drop policy if exists "read classroom state" on public.classroom_state;
create policy "read classroom state" on public.classroom_state for select to authenticated using (true);

-- Restrict direct profile writes. Role changes happen only in trusted SQL/admin setup.
revoke insert, update, delete on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant select on public.students, public.spin_history, public.classroom_state to authenticated;
grant insert, update, delete on public.students, public.spin_history to authenticated;

create or replace function public.draw_next_student()
returns table(student_name text, student_id uuid, spin_no integer)
language plpgsql security definer set search_path=public
as $$
declare chosen public.students%rowtype; next_no integer;
begin
 if auth.uid() is null or public.current_app_role() not in ('admin','developer') then
   raise exception 'Akses ditolak: hanya Admin/Developer yang dapat melakukan spin';
 end if;
 perform id from public.classroom_state where id=1 for update;
 select coalesce(max(sh.spin_no),0)+1 into next_no from public.spin_history sh;
 if next_no>42 then raise exception 'Semua 42 kursi sudah terisi'; end if;
 select s.* into chosen from public.students s
 where not exists(select 1 from public.spin_history h where h.student_id=s.id)
 order by random() limit 1;
 if chosen.id is null then raise exception 'Tidak ada siswa tersisa untuk diundi'; end if;
 insert into public.spin_history(student_id,student_name,spin_no)
 values(chosen.id,chosen.name,next_no);
 return query select chosen.name,chosen.id,next_no;
end; $$;

create or replace function public.undo_last_spin()
returns void language plpgsql security definer set search_path=public
as $$
begin
 if auth.uid() is null or public.current_app_role() not in ('admin','developer') then raise exception 'Akses ditolak'; end if;
 perform id from public.classroom_state where id=1 for update;
 delete from public.spin_history where spin_no=(select max(spin_no) from public.spin_history);
end; $$;

create or replace function public.reset_spins()
returns void language plpgsql security definer set search_path=public
as $$
begin
 if auth.uid() is null or public.current_app_role() not in ('admin','developer') then raise exception 'Akses ditolak'; end if;
 perform id from public.classroom_state where id=1 for update;
 delete from public.spin_history;
end; $$;

revoke all on function public.draw_next_student() from public, anon;
revoke all on function public.undo_last_spin() from public, anon;
revoke all on function public.reset_spins() from public, anon;
grant execute on function public.draw_next_student() to authenticated;
grant execute on function public.undo_last_spin() to authenticated;
grant execute on function public.reset_spins() to authenticated;

-- REALTIME: enable for tables used by the live dashboard (Dashboard > Database > Replication).


-- =========================================================
-- CLASS SEAT SPINNER UPGRADE: MAINTENANCE + SECRET SEATING
-- Safe to run after the original schema.
-- =========================================================

-- Each result has a draw sequence (spin_no) and a physical seat (seat_no).
alter table public.spin_history add column if not exists seat_no integer;
update public.spin_history set seat_no=spin_no where seat_no is null;
alter table public.spin_history alter column seat_no set not null;
create unique index if not exists spin_history_seat_no_unique on public.spin_history(seat_no);
do $$ begin
  if not exists (select 1 from pg_constraint where conname='spin_history_seat_no_range') then
    alter table public.spin_history add constraint spin_history_seat_no_range check (seat_no between 1 and 42);
  end if;
end $$;

create table if not exists public.seat_assignments (
  student_id uuid primary key references public.students(id) on delete cascade,
  seat_no integer not null unique check (seat_no between 1 and 42),
  created_at timestamptz not null default now()
);
alter table public.seat_assignments enable row level security;
revoke all on public.seat_assignments from anon, authenticated;

alter table public.classroom_state
  add column if not exists maintenance_enabled boolean not null default false,
  add column if not exists maintenance_message text not null default 'Class Seat Spinner sedang melakukan pembaruan.',
  add column if not exists maintenance_start timestamptz,
  add column if not exists maintenance_end timestamptz;

-- Public may read only the maintenance status through this narrow function.
create or replace function public.get_public_maintenance()
returns table(enabled boolean, message text, start_at timestamptz, end_at timestamptz)
language sql stable security definer set search_path=public
as $$
  select
    maintenance_enabled
      and (maintenance_start is null or maintenance_start <= now())
      and (maintenance_end is null or maintenance_end > now()),
    maintenance_message, maintenance_start, maintenance_end
  from public.classroom_state where id=1
$$;
revoke all on function public.get_public_maintenance() from public;
grant execute on function public.get_public_maintenance() to anon, authenticated;

create or replace function public.set_maintenance(
  p_enabled boolean, p_message text, p_start_at timestamptz default null, p_end_at timestamptz default null
)
returns void language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or public.current_app_role() <> 'developer' then
    raise exception 'Akses ditolak: hanya Developer.';
  end if;
  if p_start_at is not null and p_end_at is not null and p_end_at <= p_start_at then
    raise exception 'Waktu selesai harus setelah waktu mulai.';
  end if;
  update public.classroom_state
  set maintenance_enabled=p_enabled,
      maintenance_message=coalesce(nullif(trim(p_message),''),'Class Seat Spinner sedang melakukan pembaruan.'),
      maintenance_start=p_start_at,
      maintenance_end=p_end_at,
      updated_at=now()
  where id=1;
end;
$$;
revoke all on function public.set_maintenance(boolean,text,timestamptz,timestamptz) from public, anon;
grant execute on function public.set_maintenance(boolean,text,timestamptz,timestamptz) to authenticated;

create or replace function public.get_developer_assignments()
returns table(student_id uuid, student_name text, seat_no integer)
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or public.current_app_role() <> 'developer' then
    raise exception 'Akses ditolak: hanya Developer.';
  end if;
  return query
    select a.student_id, s.name, a.seat_no
    from public.seat_assignments a join public.students s on s.id=a.student_id
    order by a.seat_no;
end;
$$;
revoke all on function public.get_developer_assignments() from public, anon;
grant execute on function public.get_developer_assignments() to authenticated;

create or replace function public.set_seat_assignment(p_student_id uuid, p_seat_no integer)
returns void language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or public.current_app_role() <> 'developer' then
    raise exception 'Akses ditolak: hanya Developer.';
  end if;
  if p_seat_no < 1 or p_seat_no > 42 then raise exception 'Nomor kursi harus 1 sampai 42.'; end if;
  if not exists(select 1 from public.students where id=p_student_id) then
    raise exception 'Siswa tidak ditemukan.';
  end if;
  if exists(select 1 from public.spin_history where student_id=p_student_id) then
    raise exception 'Siswa sudah mendapatkan hasil spin.';
  end if;
  if exists(select 1 from public.spin_history where seat_no=p_seat_no) then
    raise exception 'Kursi tersebut sudah terisi.';
  end if;
  insert into public.seat_assignments(student_id,seat_no)
  values(p_student_id,p_seat_no)
  on conflict(student_id) do update set seat_no=excluded.seat_no, created_at=now();
end;
$$;
revoke all on function public.set_seat_assignment(uuid,integer) from public, anon;
grant execute on function public.set_seat_assignment(uuid,integer) to authenticated;

create or replace function public.clear_seat_assignment(p_student_id uuid)
returns void language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or public.current_app_role() <> 'developer' then
    raise exception 'Akses ditolak: hanya Developer.';
  end if;
  delete from public.seat_assignments where student_id=p_student_id;
end;
$$;
revoke all on function public.clear_seat_assignment(uuid) from public, anon;
grant execute on function public.clear_seat_assignment(uuid) to authenticated;

-- Recreate RPC because its return shape now includes physical seat_no.
drop function if exists public.draw_next_student();
create function public.draw_next_student()
returns table(student_name text, student_id uuid, spin_no integer, seat_no integer)
language plpgsql security definer set search_path=public
as $$
declare
  chosen public.students%rowtype;
  next_no integer;
  next_seat integer;
begin
  if auth.uid() is null or public.current_app_role() not in ('admin','developer') then
    raise exception 'Akses ditolak: hanya Admin/Developer yang dapat melakukan spin';
  end if;
  perform id from public.classroom_state where id=1 for update;
  select coalesce(max(sh.spin_no),0)+1 into next_no from public.spin_history sh;
  if next_no>42 then raise exception 'Semua 42 kursi sudah terisi'; end if;

  select n into next_seat
  from generate_series(1,42) n
  where not exists(select 1 from public.spin_history h where h.seat_no=n)
  order by n limit 1;
  if next_seat is null then raise exception 'Semua kursi sudah terisi'; end if;

  -- If this seat is reserved, draw its assigned student. Otherwise draw
  -- randomly among students who do not have a reserved seat.
  select s.* into chosen
  from public.seat_assignments a
  join public.students s on s.id=a.student_id
  where a.seat_no=next_seat
    and not exists(select 1 from public.spin_history h where h.student_id=s.id)
  limit 1;

  if chosen.id is null then
    select s.* into chosen
    from public.students s
    where not exists(select 1 from public.spin_history h where h.student_id=s.id)
      and not exists(select 1 from public.seat_assignments a where a.student_id=s.id)
    order by random() limit 1;
  end if;

  -- If all remaining students are reserved for later seat numbers, jump to
  -- the earliest reserved seat instead of failing because of empty gaps.
  if chosen.id is null then
    select s.* into chosen
    from public.seat_assignments a
    join public.students s on s.id=a.student_id
    where not exists(select 1 from public.spin_history h where h.student_id=s.id)
    order by a.seat_no limit 1;
    if chosen.id is not null then
      select a.seat_no into next_seat
      from public.seat_assignments a where a.student_id=chosen.id;
    end if;
  end if;

  if chosen.id is null then
    raise exception 'Tidak ada siswa yang dapat ditempatkan. Periksa pengaturan kursi rahasia.';
  end if;

  insert into public.spin_history(student_id,student_name,spin_no,seat_no)
  values(chosen.id,chosen.name,next_no,next_seat);
  return query select chosen.name,chosen.id,next_no,next_seat;
end;
$$;
revoke all on function public.draw_next_student() from public, anon;
grant execute on function public.draw_next_student() to authenticated;

-- Enable realtime for the live tables if not already published.
do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='students') then
      alter publication supabase_realtime add table public.students;
    end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='spin_history') then
      alter publication supabase_realtime add table public.spin_history;
    end if;
  end if;
end $$;
