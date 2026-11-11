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
create policy "users read own profile; staff read profiles" on public.profiles for select to authenticated using (id = auth.uid() or public.current_app_role() in ('admin','developer'));
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
