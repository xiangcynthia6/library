-- 已安装 v5/v6 的项目运行此升级脚本。不删除资源或账号。可重复运行。
begin;
create table if not exists public.resource_notifications (
 id uuid primary key default gen_random_uuid(),
 recipient_id uuid not null references auth.users(id) on delete cascade,
 resource_id uuid not null,
 resource_name text not null,
 reason text not null,
 created_at timestamptz not null default now(),
 read_at timestamptz,
 check(length(reason) between 1 and 500)
);
create index if not exists notifications_recipient_date on public.resource_notifications(recipient_id,created_at desc,id);
alter table public.resource_notifications enable row level security;
revoke all on public.resource_notifications from public,anon,authenticated;
grant select on public.resource_notifications to authenticated;
drop policy if exists notifications_self_read on public.resource_notifications;
create policy notifications_self_read on public.resource_notifications for select to authenticated using(recipient_id=auth.uid());
create or replace function resource_private.notify_resource_deleted()
returns trigger language plpgsql security definer set search_path='' as $$
declare why text;
begin
 -- 本人从网页删除不通知；控制台删除通常没有 auth.uid()，会通知当前所属账号。
 if old.owner_id is null or old.owner_id=auth.uid() then return old; end if;
 why:=nullif(btrim(current_setting('hazama.delete_reason',true)),'');
 insert into public.resource_notifications(recipient_id,resource_id,resource_name,reason)
 values(old.owner_id,old.id,old.name,coalesce(why,'该资源已被管理员移除。如有疑问，请联系网站管理员。'));
 return old;
end $$;
revoke all on function resource_private.notify_resource_deleted() from public,anon,authenticated;
drop trigger if exists resources_delete_notice on public.resources;
create trigger resources_delete_notice after delete on public.resources for each row execute function resource_private.notify_resource_deleted();
create or replace function public.hazama_delete_with_notice(p_id uuid,p_version integer,p_reason text default '')
returns boolean language plpgsql security definer set search_path='' as $$
declare previous_reason text;
begin
 if auth.uid() is null then raise exception '请先登录'; end if;
 if length(coalesce(p_reason,''))>500 then raise exception '删除原因不能超过 500 字'; end if;
 previous_reason:=current_setting('hazama.delete_reason',true);
 perform set_config('hazama.delete_reason',coalesce(nullif(btrim(p_reason),''),'该资源已被管理员移除。如有疑问，请联系网站管理员。'),true);
 delete from public.resources where id=p_id and version=p_version and (owner_id=auth.uid() or public.hazama_is_admin());
 if not found then raise exception '无权删除，或资源已发生变化，请刷新后重试'; end if;
 perform set_config('hazama.delete_reason',coalesce(previous_reason,''),true);
 return true;
end $$;
create or replace function public.hazama_notice_read(p_ids uuid[])
returns integer language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 if auth.uid() is null then raise exception '请先登录'; end if;
 if coalesce(array_length(p_ids,1),0)>100 then raise exception '一次最多标记 100 条'; end if;
 update public.resource_notifications set read_at=now() where id=any(p_ids) and recipient_id=auth.uid() and read_at is null;
 get diagnostics n=row_count;return n;
end $$;
revoke all on function public.hazama_delete_with_notice(uuid,integer,text),public.hazama_notice_read(uuid[]) from public,anon,authenticated;
grant execute on function public.hazama_delete_with_notice(uuid,integer,text),public.hazama_notice_read(uuid[]) to authenticated;
create or replace function public.hazama_version() returns integer language sql immutable set search_path='' as $$select 7$$;
-- 普通访客无法订阅其他用户的通知，SELECT RLS 决定可见范围。
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='resource_notifications') then
 alter publication supabase_realtime add table public.resource_notifications;
 end if;
end $$;
notify pgrst,'reload schema';
commit;
