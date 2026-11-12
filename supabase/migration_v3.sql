-- CLASS SEAT SPINNER V3: CLASSROOM + QR ATTENDANCE
-- Run AFTER migration_v2.sql. Additive: does not delete existing students, spin history, accounts, or settings.
create extension if not exists pgcrypto;

-- Link each login account to exactly one student record (admin/developer assigns this).
alter table public.profiles add column if not exists student_id uuid references public.students(id) on delete set null;
create index if not exists profiles_student_id_idx on public.profiles(student_id);
alter table public.students add column if not exists student_no text;
alter table public.students add column if not exists photo_url text;
alter table public.students add column if not exists profile_note text;

-- Attendance sessions and records.
create table if not exists public.attendance_sessions (
 id uuid primary key default gen_random_uuid(),
 title text not null default 'Absensi Kelas',
 token_hash text not null unique,
 status text not null default 'open' check(status in ('open','closed')),
 opens_at timestamptz not null default now(),
 expires_at timestamptz not null,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 closed_at timestamptz
);
create index if not exists attendance_sessions_created_idx on public.attendance_sessions(created_at desc);
create table if not exists public.attendance_records (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.attendance_sessions(id) on delete cascade,
 student_id uuid not null references public.students(id) on delete cascade,
 status text not null check(status in ('hadir','izin','sakit','alpa')),
 method text not null default 'qr' check(method in ('qr','admin')),
 marked_by uuid references auth.users(id) on delete set null,
 marked_at timestamptz not null default now(),
 note text,
 unique(session_id,student_id)
);
create index if not exists attendance_records_student_idx on public.attendance_records(student_id,marked_at desc);

-- Class calendar, announcements, and student suggestions.
create table if not exists public.class_events (
 id uuid primary key default gen_random_uuid(),
 title text not null,
 description text not null default '',
 starts_at timestamptz not null,
 ends_at timestamptz,
 location text not null default '',
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 constraint class_events_valid_range check(ends_at is null or ends_at >= starts_at)
);
create index if not exists class_events_starts_idx on public.class_events(starts_at);
create table if not exists public.class_announcements (
 id uuid primary key default gen_random_uuid(),
 title text not null,
 body text not null,
 priority text not null default 'normal' check(priority in ('normal','important')),
 publish_at timestamptz not null default now(),
 expires_at timestamptz,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now()
);
create index if not exists class_announcements_publish_idx on public.class_announcements(publish_at desc);
create table if not exists public.class_suggestions (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 student_id uuid references public.students(id) on delete set null,
 message text not null,
 anonymous_to_students boolean not null default true,
 status text not null default 'baru' check(status in ('baru','diproses','selesai')),
 admin_reply text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists class_suggestions_created_idx on public.class_suggestions(created_at desc);

alter table public.attendance_sessions enable row level security;
alter table public.attendance_records enable row level security;
alter table public.class_events enable row level security;
alter table public.class_announcements enable row level security;
alter table public.class_suggestions enable row level security;

-- seat_assignments: allow only Developer to read directly for secure backup export.
drop policy if exists "developers can read seat assignments for backup" on public.seat_assignments;
create policy "developers can read seat assignments for backup"
on public.seat_assignments for select to authenticated
using (public.current_app_role()='developer');
grant select on public.seat_assignments to authenticated;

-- Profiles can be read as already defined in V2. Only staff can read full student links.
-- Account-to-student mapping is performed through a guarded RPC.
drop policy if exists "staff read attendance sessions" on public.attendance_sessions;
create policy "staff read attendance sessions" on public.attendance_sessions for select to authenticated
using (public.current_app_role() in ('admin','developer'));
drop policy if exists "staff read attendance records" on public.attendance_records;
create policy "staff read attendance records" on public.attendance_records for select to authenticated
using (public.current_app_role() in ('admin','developer') or student_id=(select p.student_id from public.profiles p where p.id=auth.uid()));
drop policy if exists "staff manage attendance records" on public.attendance_records;
create policy "staff manage attendance records" on public.attendance_records for all to authenticated
using (public.current_app_role() in ('admin','developer'))
with check (public.current_app_role() in ('admin','developer'));
drop policy if exists "authenticated read class events" on public.class_events;
create policy "authenticated read class events" on public.class_events for select to authenticated using (true);
drop policy if exists "staff manage class events" on public.class_events;
create policy "staff manage class events" on public.class_events for all to authenticated
using (public.current_app_role() in ('admin','developer'))
with check (public.current_app_role() in ('admin','developer'));
drop policy if exists "authenticated read announcements" on public.class_announcements;
create policy "authenticated read announcements" on public.class_announcements for select to authenticated
using (publish_at <= now() and (expires_at is null or expires_at > now()) or public.current_app_role() in ('admin','developer'));
drop policy if exists "staff manage announcements" on public.class_announcements;
create policy "staff manage announcements" on public.class_announcements for all to authenticated
using (public.current_app_role() in ('admin','developer'))
with check (public.current_app_role() in ('admin','developer'));
drop policy if exists "users submit own suggestions" on public.class_suggestions;
create policy "users submit own suggestions" on public.class_suggestions for insert to authenticated
with check (user_id=auth.uid());
drop policy if exists "users read own suggestions; staff read all" on public.class_suggestions;
create policy "users read own suggestions; staff read all" on public.class_suggestions for select to authenticated
using (user_id=auth.uid() or public.current_app_role() in ('admin','developer'));
drop policy if exists "staff update suggestions" on public.class_suggestions;
create policy "staff update suggestions" on public.class_suggestions for update to authenticated
using (public.current_app_role() in ('admin','developer'))
with check (public.current_app_role() in ('admin','developer'));

grant select on public.attendance_sessions, public.attendance_records, public.class_events, public.class_announcements, public.class_suggestions to authenticated;
grant insert,update,delete on public.attendance_records to authenticated;
grant select,insert,update,delete on public.class_events, public.class_announcements to authenticated;
grant insert,select on public.class_suggestions to authenticated;
grant update on public.class_suggestions to authenticated;

-- Create a time-limited one-time QR session. Plain token is returned only to staff;
-- only its SHA-256 hash is stored in the database.
create or replace function public.create_attendance_session(p_title text default 'Absensi Kelas', p_valid_minutes integer default 10)
returns table(session_id uuid, qr_token text, expires_at timestamptz)
language plpgsql security definer set search_path=public
as $$
declare v_token text; v_id uuid; v_exp timestamptz;
begin
 if auth.uid() is null or public.current_app_role() not in ('admin','developer') then raise exception 'Hanya Admin/Developer yang dapat membuka absensi.'; end if;
 if p_valid_minutes < 1 or p_valid_minutes > 60 then raise exception 'Masa berlaku QR harus 1-60 menit.'; end if;
 update public.attendance_sessions set status='closed',closed_at=now() where status='open';
 v_token := encode(gen_random_bytes(24),'hex');
 v_exp := now() + make_interval(mins => p_valid_minutes);
 insert into public.attendance_sessions(title,token_hash,expires_at,created_by)
 values(left(coalesce(nullif(trim(p_title),''),'Absensi Kelas'),100),encode(digest(v_token,'sha256'),'hex'),v_exp,auth.uid())
 returning id into v_id;
 return query select v_id,v_token,v_exp;
end $$;
revoke all on function public.create_attendance_session(text,integer) from public,anon;
grant execute on function public.create_attendance_session(text,integer) to authenticated;

create or replace function public.scan_attendance_qr(p_token text)
returns table(student_name text, marked_at timestamptz, attendance_status text)
language plpgsql security definer set search_path=public
as $$
declare v_session public.attendance_sessions%rowtype; v_student uuid; v_name text;
begin
 if auth.uid() is null then raise exception 'Silakan login terlebih dahulu.'; end if;
 select p.student_id into v_student from public.profiles p where p.id=auth.uid();
 if v_student is null then raise exception 'Akun belum dihubungkan ke data siswa. Hubungi Admin.'; end if;
 select * into v_session from public.attendance_sessions
 where token_hash=encode(digest(coalesce(p_token,''),'sha256'),'hex')
 for update;
 if v_session.id is null then raise exception 'QR tidak valid.'; end if;
 if v_session.status<>'open' or v_session.expires_at<=now() then raise exception 'Sesi absensi sudah ditutup atau QR kedaluwarsa.'; end if;
 select s.name into v_name from public.students s where s.id=v_student;
 if v_name is null then raise exception 'Data siswa tidak ditemukan.'; end if;
 insert into public.attendance_records(session_id,student_id,status,method,marked_by)
 values(v_session.id,v_student,'hadir','qr',auth.uid())
 on conflict(session_id,student_id) do nothing;
 if not found then raise exception 'Kamu sudah melakukan absensi untuk sesi ini.'; end if;
 return query select v_name,now(),'hadir'::text;
end $$;
revoke all on function public.scan_attendance_qr(text) from public,anon;
grant execute on function public.scan_attendance_qr(text) to authenticated;

create or replace function public.close_attendance_session(p_session_id uuid)
returns void language plpgsql security definer set search_path=public
as $$
begin
 if auth.uid() is null or public.current_app_role() not in ('admin','developer') then raise exception 'Akses ditolak.'; end if;
 update public.attendance_sessions set status='closed',closed_at=now() where id=p_session_id;
end $$;
revoke all on function public.close_attendance_session(uuid) from public,anon;
grant execute on function public.close_attendance_session(uuid) to authenticated;

create or replace function public.mark_attendance_manual(p_session_id uuid,p_student_id uuid,p_status text,p_note text default '')
returns void language plpgsql security definer set search_path=public
as $$
begin
 if auth.uid() is null or public.current_app_role() not in ('admin','developer') then raise exception 'Hanya Admin/Developer yang dapat mengubah absensi.'; end if;
 if p_status not in ('hadir','izin','sakit','alpa') then raise exception 'Status absensi tidak valid.'; end if;
 if not exists(select 1 from public.attendance_sessions where id=p_session_id) then raise exception 'Sesi tidak ditemukan.'; end if;
 insert into public.attendance_records(session_id,student_id,status,method,marked_by,note)
 values(p_session_id,p_student_id,p_status,'admin',auth.uid(),left(coalesce(p_note,''),300))
 on conflict(session_id,student_id) do update set status=excluded.status,method='admin',marked_by=auth.uid(),marked_at=now(),note=excluded.note;
end $$;
revoke all on function public.mark_attendance_manual(uuid,uuid,text,text) from public,anon;
grant execute on function public.mark_attendance_manual(uuid,uuid,text,text) to authenticated;

create or replace function public.link_student_account(p_user_id uuid,p_student_id uuid)
returns void language plpgsql security definer set search_path=public
as $$
begin
 if auth.uid() is null or public.current_app_role() not in ('admin','developer') then raise exception 'Akses ditolak.'; end if;
 if p_student_id is not null and not exists(select 1 from public.students where id=p_student_id) then raise exception 'Siswa tidak ditemukan.'; end if;
 if exists(select 1 from public.profiles where student_id=p_student_id and id<>p_user_id) and p_student_id is not null then raise exception 'Siswa ini sudah terhubung ke akun lain.'; end if;
 update public.profiles set student_id=p_student_id where id=p_user_id;
end $$;
revoke all on function public.link_student_account(uuid,uuid) from public,anon;
grant execute on function public.link_student_account(uuid,uuid) to authenticated;

create or replace function public.submit_class_suggestion(p_message text,p_anonymous boolean default true)
returns uuid language plpgsql security definer set search_path=public
as $$
declare v_id uuid; v_student uuid;
begin
 if auth.uid() is null then raise exception 'Silakan login.'; end if;
 if length(trim(coalesce(p_message,'')))<3 or length(p_message)>2000 then raise exception 'Saran harus berisi 3-2000 karakter.'; end if;
 select student_id into v_student from public.profiles where id=auth.uid();
 insert into public.class_suggestions(user_id,student_id,message,anonymous_to_students)
 values(auth.uid(),v_student,trim(p_message),coalesce(p_anonymous,true)) returning id into v_id;
 return v_id;
end $$;
revoke all on function public.submit_class_suggestion(text,boolean) from public,anon;
grant execute on function public.submit_class_suggestion(text,boolean) to authenticated;

-- Allow realtime updates for classroom modules.
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='attendance_records') then alter publication supabase_realtime add table public.attendance_records; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='class_events') then alter publication supabase_realtime add table public.class_events; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='class_announcements') then alter publication supabase_realtime add table public.class_announcements; end if;
 end if;
end $$;


-- V3 full backup restore. QR sessions are restored as CLOSED and receive fresh random hashes,
-- so an old exported QR token can never be reused after restore.
create or replace function public.restore_classroom_backup_v3(p_payload jsonb)
returns void language plpgsql security definer set search_path=public
as $$
declare v_item jsonb; v_new_hash text;
begin
 if auth.uid() is null or public.current_app_role()<>'developer' then raise exception 'Akses ditolak: hanya Developer yang dapat restore backup.'; end if;
 if jsonb_typeof(p_payload->'students')<>'array' or jsonb_typeof(p_payload->'spin_history')<>'array' then raise exception 'Format backup tidak valid.'; end if;
 if jsonb_array_length(p_payload->'students')>42 or jsonb_array_length(p_payload->'spin_history')>42 then raise exception 'Backup melebihi kapasitas 42 kursi.'; end if;

 -- Clear dependent classroom data first; keep auth accounts and app settings untouched.
 delete from public.attendance_sessions;
 delete from public.class_events;
 delete from public.class_announcements;
 delete from public.class_suggestions;
 delete from public.spin_history;
 delete from public.seat_assignments;
 delete from public.students;

 for v_item in select value from jsonb_array_elements(coalesce(p_payload->'students','[]'::jsonb)) loop
  insert into public.students(id,name,sort_order,created_at,student_no,photo_url,profile_note)
  values((v_item->>'id')::uuid,left(v_item->>'name',120),coalesce((v_item->>'sort_order')::integer,0),
   coalesce((v_item->>'created_at')::timestamptz,now()),v_item->>'student_no',v_item->>'photo_url',v_item->>'profile_note');
 end loop;
 for v_item in select value from jsonb_array_elements(coalesce(p_payload->'spin_history','[]'::jsonb)) loop
  insert into public.spin_history(id,student_id,student_name,spin_no,created_at,seat_no)
  values((v_item->>'id')::uuid,(v_item->>'student_id')::uuid,v_item->>'student_name',(v_item->>'spin_no')::integer,
   coalesce((v_item->>'created_at')::timestamptz,now()),coalesce((v_item->>'seat_no')::integer,(v_item->>'spin_no')::integer));
 end loop;
 for v_item in select value from jsonb_array_elements(coalesce(p_payload->'seat_assignments','[]'::jsonb)) loop
  insert into public.seat_assignments(student_id,seat_no) values((v_item->>'student_id')::uuid,(v_item->>'seat_no')::integer) on conflict do nothing;
 end loop;

 for v_item in select value from jsonb_array_elements(coalesce(p_payload->'attendance_sessions','[]'::jsonb)) loop
  insert into public.attendance_sessions(id,title,token_hash,status,opens_at,expires_at,created_by,created_at,closed_at)
  values((v_item->>'id')::uuid,left(coalesce(v_item->>'title','Absensi Kelas'),100),
   encode(digest(encode(gen_random_bytes(24),'hex'),'sha256'),'hex'),'closed',
   coalesce((v_item->>'opens_at')::timestamptz,now()),coalesce((v_item->>'expires_at')::timestamptz,now()),
   null,coalesce((v_item->>'created_at')::timestamptz,now()),now());
 end loop;
 for v_item in select value from jsonb_array_elements(coalesce(p_payload->'attendance_records','[]'::jsonb)) loop
  insert into public.attendance_records(id,session_id,student_id,status,method,marked_by,marked_at,note)
  values((v_item->>'id')::uuid,(v_item->>'session_id')::uuid,(v_item->>'student_id')::uuid,v_item->>'status',
   coalesce(v_item->>'method','admin'),null,coalesce((v_item->>'marked_at')::timestamptz,now()),v_item->>'note');
 end loop;
 for v_item in select value from jsonb_array_elements(coalesce(p_payload->'class_events','[]'::jsonb)) loop
  insert into public.class_events(id,title,description,starts_at,ends_at,location,created_by,created_at)
  values((v_item->>'id')::uuid,v_item->>'title',coalesce(v_item->>'description',''),(v_item->>'starts_at')::timestamptz,
   nullif(v_item->>'ends_at','')::timestamptz,coalesce(v_item->>'location',''),null,coalesce((v_item->>'created_at')::timestamptz,now()));
 end loop;
 for v_item in select value from jsonb_array_elements(coalesce(p_payload->'class_announcements','[]'::jsonb)) loop
  insert into public.class_announcements(id,title,body,priority,publish_at,expires_at,created_by,created_at)
  values((v_item->>'id')::uuid,v_item->>'title',v_item->>'body',coalesce(v_item->>'priority','normal'),
   coalesce((v_item->>'publish_at')::timestamptz,now()),nullif(v_item->>'expires_at','')::timestamptz,
   null,coalesce((v_item->>'created_at')::timestamptz,now()));
 end loop;
 for v_item in select value from jsonb_array_elements(coalesce(p_payload->'class_suggestions','[]'::jsonb)) loop
  if exists(select 1 from auth.users where id=(v_item->>'user_id')::uuid) then
   insert into public.class_suggestions(id,user_id,student_id,message,anonymous_to_students,status,admin_reply,created_at,updated_at)
   values((v_item->>'id')::uuid,(v_item->>'user_id')::uuid,nullif(v_item->>'student_id','')::uuid,v_item->>'message',
    coalesce((v_item->>'anonymous_to_students')::boolean,true),coalesce(v_item->>'status','baru'),v_item->>'admin_reply',
    coalesce((v_item->>'created_at')::timestamptz,now()),coalesce((v_item->>'updated_at')::timestamptz,now()));
  end if;
 end loop;
 -- Restore account-to-student links only for accounts that still exist.
 for v_item in select value from jsonb_array_elements(coalesce(p_payload->'profile_student_links','[]'::jsonb)) loop
  update public.profiles set student_id=nullif(v_item->>'student_id','')::uuid where id=(v_item->>'id')::uuid;
 end loop;
 perform public.write_activity('V3_BACKUP_RESTORED',jsonb_build_object('students',jsonb_array_length(p_payload->'students')));
end $$;
revoke all on function public.restore_classroom_backup_v3(jsonb) from public,anon;
grant execute on function public.restore_classroom_backup_v3(jsonb) to authenticated;
