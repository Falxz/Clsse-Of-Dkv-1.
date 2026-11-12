-- CLASS SEAT SPINNER V2 UPGRADE
-- Run AFTER the existing premium schema.sql. Safe additive migration; no existing student/history rows are deleted.
create extension if not exists pgcrypto;

alter table public.profiles add column if not exists is_disabled boolean not null default false;

create table if not exists public.activity_logs (
 id uuid primary key default gen_random_uuid(),
 actor_id uuid references auth.users(id) on delete set null,
 actor_name text not null default 'System',
 action text not null,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index if not exists activity_logs_created_at_idx on public.activity_logs(created_at desc);

create table if not exists public.seating_snapshots (
 id uuid primary key default gen_random_uuid(),
 name text not null,
 created_by uuid references auth.users(id) on delete set null,
 payload jsonb not null,
 created_at timestamptz not null default now()
);

create table if not exists public.app_settings (
 id integer primary key default 1 check(id=1),
 class_name text not null default 'CLASS SEAT SPINNER',
 accent_color text not null default '#77aaff',
 spin_duration_ms integer not null default 1250 check(spin_duration_ms between 500 and 8000),
 spin_sound boolean not null default false,
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id) on delete set null
);
insert into public.app_settings(id) values(1) on conflict do nothing;

alter table public.activity_logs enable row level security;
alter table public.seating_snapshots enable row level security;
alter table public.app_settings enable row level security;

drop policy if exists "authenticated read activity logs" on public.activity_logs;
create policy "authenticated read activity logs" on public.activity_logs for select to authenticated using (true);
drop policy if exists "developer manage activity logs" on public.activity_logs;
create policy "developer manage activity logs" on public.activity_logs for all to authenticated using (public.current_app_role()='developer') with check (public.current_app_role()='developer');
drop policy if exists "staff read snapshots" on public.seating_snapshots;
create policy "staff read snapshots" on public.seating_snapshots for select to authenticated using (public.current_app_role() in ('admin','developer'));
drop policy if exists "staff create snapshots" on public.seating_snapshots;
create policy "staff create snapshots" on public.seating_snapshots for insert to authenticated with check (public.current_app_role() in ('admin','developer'));
drop policy if exists "developer manage app settings" on public.app_settings;
create policy "developer manage app settings" on public.app_settings for all to authenticated using (public.current_app_role()='developer') with check (public.current_app_role()='developer');
grant select on public.activity_logs, public.seating_snapshots to authenticated;
grant insert on public.seating_snapshots to authenticated;
grant select,insert,update on public.app_settings to authenticated;

create or replace function public.write_activity(p_action text,p_details jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public
as $$
declare v_name text;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select coalesce(display_name,email,'User') into v_name from public.profiles where id=auth.uid();
 insert into public.activity_logs(actor_id,actor_name,action,details) values(auth.uid(),coalesce(v_name,'User'),left(p_action,100),coalesce(p_details,'{}'::jsonb));
end; $$;
revoke all on function public.write_activity(text,jsonb) from public,anon;
grant execute on function public.write_activity(text,jsonb) to authenticated;

create or replace function public.get_app_settings()
returns table(class_name text,accent_color text,spin_duration_ms integer,spin_sound boolean)
language sql stable security definer set search_path=public
as $$ select class_name,accent_color,spin_duration_ms,spin_sound from public.app_settings where id=1 $$;
revoke all on function public.get_app_settings() from public;
grant execute on function public.get_app_settings() to authenticated;

create or replace function public.save_app_settings(p_class_name text,p_accent_color text,p_spin_duration_ms integer,p_spin_sound boolean)
returns void language plpgsql security definer set search_path=public
as $$
begin
 if auth.uid() is null or public.current_app_role()<>'developer' then raise exception 'Akses ditolak: hanya Developer.'; end if;
 if p_spin_duration_ms not between 500 and 8000 then raise exception 'Durasi spin harus 500-8000 ms.'; end if;
 if p_accent_color !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Warna aksen tidak valid.'; end if;
 update public.app_settings set class_name=left(coalesce(nullif(trim(p_class_name),''),'CLASS SEAT SPINNER'),80),accent_color=p_accent_color,spin_duration_ms=p_spin_duration_ms,spin_sound=p_spin_sound,updated_at=now(),updated_by=auth.uid() where id=1;
end; $$;
revoke all on function public.save_app_settings(text,text,integer,boolean) from public,anon;
grant execute on function public.save_app_settings(text,text,integer,boolean) to authenticated;

create or replace function public.create_seating_snapshot(p_name text)
returns uuid language plpgsql security definer set search_path=public
as $$
declare v_id uuid; v_payload jsonb;
begin
 if auth.uid() is null or public.current_app_role() not in ('admin','developer') then raise exception 'Akses ditolak.'; end if;
 select jsonb_build_object(
  'students',(select coalesce(jsonb_agg(to_jsonb(s) order by sort_order), '[]'::jsonb) from public.students s),
  'spin_history',(select coalesce(jsonb_agg(to_jsonb(h) order by spin_no), '[]'::jsonb) from public.spin_history h),
  'seat_assignments',(select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) from public.seat_assignments a)
 ) into v_payload;
 insert into public.seating_snapshots(name,created_by,payload) values(left(coalesce(nullif(trim(p_name),''),'Snapshot '+to_char(now(),'YYYY-MM-DD HH24:MI')),100),auth.uid(),v_payload) returning id into v_id;
 perform public.write_activity('SEATING_SNAPSHOT_CREATED',jsonb_build_object('snapshot_id',v_id,'name',p_name));
 return v_id;
end; $$;
revoke all on function public.create_seating_snapshot(text) from public,anon;
grant execute on function public.create_seating_snapshot(text) to authenticated;

create or replace function public.restore_seating_snapshot(p_snapshot_id uuid)
returns void language plpgsql security definer set search_path=public
as $$
declare v_payload jsonb; v_item jsonb;
begin
 if auth.uid() is null or public.current_app_role()<>'developer' then raise exception 'Akses ditolak: hanya Developer yang dapat restore.'; end if;
 select payload into v_payload from public.seating_snapshots where id=p_snapshot_id;
 if v_payload is null then raise exception 'Snapshot tidak ditemukan.'; end if;
 -- Restore only existing student IDs and their spin records. Existing rows not in snapshot are removed.
 delete from public.spin_history;
 delete from public.students;
 for v_item in select value from jsonb_array_elements(coalesce(v_payload->'students','[]'::jsonb)) loop
  insert into public.students(id,name,sort_order,created_at) values((v_item->>'id')::uuid,v_item->>'name',coalesce((v_item->>'sort_order')::integer,0),coalesce((v_item->>'created_at')::timestamptz,now()));
 end loop;
 for v_item in select value from jsonb_array_elements(coalesce(v_payload->'spin_history','[]'::jsonb)) loop
  insert into public.spin_history(id,student_id,student_name,spin_no,created_at,seat_no)
  values((v_item->>'id')::uuid,(v_item->>'student_id')::uuid,v_item->>'student_name',(v_item->>'spin_no')::integer,coalesce((v_item->>'created_at')::timestamptz,now()),coalesce((v_item->>'seat_no')::integer,(v_item->>'spin_no')::integer));
 end loop;
 if to_regclass('public.seat_assignments') is not null then
  delete from public.seat_assignments;
  for v_item in select value from jsonb_array_elements(coalesce(v_payload->'seat_assignments','[]'::jsonb)) loop
   insert into public.seat_assignments(student_id,seat_no) values((v_item->>'student_id')::uuid,(v_item->>'seat_no')::integer) on conflict do nothing;
  end loop;
 end if;
 perform public.write_activity('SEATING_SNAPSHOT_RESTORED',jsonb_build_object('snapshot_id',p_snapshot_id));
end; $$;
revoke all on function public.restore_seating_snapshot(uuid) from public,anon;
grant execute on function public.restore_seating_snapshot(uuid) to authenticated;

create or replace function public.restore_classroom_backup(p_payload jsonb)
returns void language plpgsql security definer set search_path=public
as $$
declare v_item jsonb;
begin
 if auth.uid() is null or public.current_app_role()<>'developer' then raise exception 'Akses ditolak: hanya Developer yang dapat restore backup.'; end if;
 if jsonb_typeof(p_payload->'students')<>'array' or jsonb_typeof(p_payload->'spin_history')<>'array' then raise exception 'Format backup tidak valid.'; end if;
 if jsonb_array_length(p_payload->'students')>42 or jsonb_array_length(p_payload->'spin_history')>42 then raise exception 'Backup melebihi kapasitas 42 kursi.'; end if;
 delete from public.spin_history;
 delete from public.seat_assignments;
 delete from public.students;
 for v_item in select value from jsonb_array_elements(p_payload->'students') loop
  insert into public.students(id,name,sort_order,created_at) values((v_item->>'id')::uuid,left(v_item->>'name',120),coalesce((v_item->>'sort_order')::integer,0),coalesce((v_item->>'created_at')::timestamptz,now()));
 end loop;
 for v_item in select value from jsonb_array_elements(p_payload->'spin_history') loop
  insert into public.spin_history(id,student_id,student_name,spin_no,created_at,seat_no)
  values((v_item->>'id')::uuid,(v_item->>'student_id')::uuid,v_item->>'student_name',(v_item->>'spin_no')::integer,coalesce((v_item->>'created_at')::timestamptz,now()),coalesce((v_item->>'seat_no')::integer,(v_item->>'spin_no')::integer));
 end loop;
 for v_item in select value from jsonb_array_elements(coalesce(p_payload->'seat_assignments','[]'::jsonb)) loop
  insert into public.seat_assignments(student_id,seat_no) values((v_item->>'student_id')::uuid,(v_item->>'seat_no')::integer) on conflict do nothing;
 end loop;
 perform public.write_activity('CLASSROOM_BACKUP_RESTORED',jsonb_build_object('student_count',jsonb_array_length(p_payload->'students'),'spin_count',jsonb_array_length(p_payload->'spin_history')));
end; $$;
revoke all on function public.restore_classroom_backup(jsonb) from public,anon;
grant execute on function public.restore_classroom_backup(jsonb) to authenticated;

-- Automatic audit events for important table mutations.
create or replace function public.audit_classroom_change()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_actor uuid; v_action text; v_details jsonb;
begin
 v_actor:=auth.uid();
 if TG_OP='INSERT' then v_action:=TG_TABLE_NAME||'_INSERT'; v_details:=to_jsonb(NEW);
 elsif TG_OP='UPDATE' then v_action:=TG_TABLE_NAME||'_UPDATE'; v_details:=jsonb_build_object('before',to_jsonb(OLD),'after',to_jsonb(NEW));
 else v_action:=TG_TABLE_NAME||'_DELETE'; v_details:=to_jsonb(OLD); end if;
 insert into public.activity_logs(actor_id,actor_name,action,details)
 values(v_actor,coalesce((select display_name from public.profiles where id=v_actor),'System'),v_action,v_details);
 if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
end; $$;
drop trigger if exists audit_students_change on public.students;
create trigger audit_students_change after insert or update or delete on public.students for each row execute function public.audit_classroom_change();
drop trigger if exists audit_spin_history_change on public.spin_history;
create trigger audit_spin_history_change after insert or update or delete on public.spin_history for each row execute function public.audit_classroom_change();

-- The existing maintenance_start / maintenance_end columns already support scheduled maintenance.
-- Effective maintenance status is evaluated by get_public_maintenance() based on server time.
