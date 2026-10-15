-- 狭间图书馆账号版 v5。新项目或旧版升级均运行此文件；先备份数据库。
-- 可重复运行；不会清空已有资源。不需要开启匿名登录。
begin;
create schema if not exists resource_private;
revoke all on schema resource_private from public, anon, authenticated;
create table if not exists public.resources (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(btrim(name)) between 1 and 120),
 quark text not null default '' check(length(quark)<=2000 and (quark='' or quark ~ '^https?://[^[:space:]]+$')),
 baidu text not null default '' check(length(baidu)<=2000 and (baidu='' or baidu ~ '^https?://[^[:space:]]+$')),
 other text not null default '' check(length(other)<=2000 and (other='' or other ~ '^https?://[^[:space:]]+$')),
 quark_code text not null default '' check(length(quark_code)<=30),
 baidu_code text not null default '' check(length(baidu_code)<=30),
 notes text not null default '' check(length(notes)<=1000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 version integer not null default 1,
 check(quark<>'' or baidu<>'' or other<>'')
);
create index if not exists resources_created on public.resources(created_at desc);

alter table public.resources add column if not exists owner_id uuid references auth.users(id) on delete set null;
create index if not exists resources_owner on public.resources(owner_id);
create table if not exists public.library_admins(user_id uuid primary key references auth.users(id) on delete cascade);
alter table public.library_admins enable row level security;
revoke all on public.library_admins from public,anon,authenticated;
grant select on public.library_admins to service_role;
alter table public.resources enable row level security;
revoke all on public.resources from public,anon,authenticated;
grant select on public.resources to anon,authenticated;
drop policy if exists resources_read on public.resources;
create policy resources_read on public.resources for select to anon,authenticated using(true);
-- 永久停用旧钥匙写入入口。私密表仍保留，避免无必要删除数据。
drop function if exists public.resource_update(uuid,text,integer,jsonb);
drop function if exists public.resource_delete(uuid,text,integer);
drop function if exists public.resource_verify(uuid,text);
drop function if exists public.resource_create(jsonb,text);
create or replace function public.hazama_version() returns integer language sql immutable set search_path='' as $$ select 5 $$;
create or replace function public.hazama_is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.library_admins where user_id=auth.uid());
$$;
create or replace function public.hazama_create(p_data jsonb)
returns public.resources language plpgsql security definer set search_path='' as $$
declare r public.resources; uid uuid:=auth.uid();
begin
 if uid is null then raise exception '请先登录'; end if;
 insert into public.resources(name,quark,baidu,other,quark_code,baidu_code,notes,owner_id)
 values(btrim(p_data->>'name'),coalesce(p_data->>'quark',''),coalesce(p_data->>'baidu',''),coalesce(p_data->>'other',''),coalesce(p_data->>'quark_code',''),coalesce(p_data->>'baidu_code',''),coalesce(p_data->>'notes',''),uid) returning * into r;
 return r;
end $$;
create or replace function public.hazama_update(p_id uuid,p_version integer,p_data jsonb)
returns public.resources language plpgsql security definer set search_path='' as $$
declare r public.resources; uid uuid:=auth.uid();
begin
 if uid is null then raise exception '请先登录'; end if;
 update public.resources set name=btrim(p_data->>'name'),quark=coalesce(p_data->>'quark',''),baidu=coalesce(p_data->>'baidu',''),other=coalesce(p_data->>'other',''),quark_code=coalesce(p_data->>'quark_code',''),baidu_code=coalesce(p_data->>'baidu_code',''),notes=coalesce(p_data->>'notes',''),updated_at=clock_timestamp(),version=version+1
 where id=p_id and owner_id=uid and version=p_version returning * into r;
 if not found then raise exception '无权编辑，或资源已发生变化，请刷新后重试'; end if;
 return r;
end $$;
create or replace function public.hazama_delete(p_id uuid,p_version integer)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception '请先登录'; end if;
 delete from public.resources where id=p_id and version=p_version and (owner_id=auth.uid() or public.hazama_is_admin());
 if not found then raise exception '无权删除，或资源已发生变化，请刷新后重试'; end if;
 return true;
end $$;
revoke all on function public.hazama_version(),public.hazama_is_admin(),public.hazama_create(jsonb),public.hazama_update(uuid,integer,jsonb),public.hazama_delete(uuid,integer) from public,anon,authenticated;
grant execute on function public.hazama_version() to anon,authenticated;
grant execute on function public.hazama_is_admin(),public.hazama_create(jsonb),public.hazama_update(uuid,integer,jsonb),public.hazama_delete(uuid,integer) to authenticated;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='resources') then
 alter publication supabase_realtime add table public.resources;
 end if;
end $$;
notify pgrst,'reload schema';
commit;

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

-- v7 升级：只运行本文件即可。可重复运行，不改变账号或资源归属。
begin;
alter table public.resources add column if not exists category text not null default '待分类';
do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.resources'::regclass and conname='resources_category_allowed') then
 alter table public.resources add constraint resources_category_allowed check(category in ('文学阅读','影视动漫','学习','绘画设计','兴趣手作','软件工具','游戏相关','待分类'));
 end if;
end $$;
create index if not exists resources_category on public.resources(category);
create or replace function public.hazama_create(p_data jsonb)
returns public.resources language plpgsql security definer set search_path='' as $$
declare r public.resources; uid uuid:=auth.uid();
begin
 if uid is null then raise exception '请先登录'; end if;
 insert into public.resources(name,quark,baidu,other,quark_code,baidu_code,notes,owner_id,category)
 values(btrim(p_data->>'name'),coalesce(p_data->>'quark',''),coalesce(p_data->>'baidu',''),coalesce(p_data->>'other',''),coalesce(p_data->>'quark_code',''),coalesce(p_data->>'baidu_code',''),coalesce(p_data->>'notes',''),uid,coalesce(p_data->>'category','待分类')) returning * into r;
 return r;
end $$;
create or replace function public.hazama_update(p_id uuid,p_version integer,p_data jsonb)
returns public.resources language plpgsql security definer set search_path='' as $$
declare r public.resources; uid uuid:=auth.uid();
begin
 if uid is null then raise exception '请先登录'; end if;
 update public.resources set category=coalesce(p_data->>'category',category),name=btrim(p_data->>'name'),quark=coalesce(p_data->>'quark',''),baidu=coalesce(p_data->>'baidu',''),other=coalesce(p_data->>'other',''),quark_code=coalesce(p_data->>'quark_code',''),baidu_code=coalesce(p_data->>'baidu_code',''),notes=coalesce(p_data->>'notes',''),updated_at=clock_timestamp(),version=version+1
 where id=p_id and owner_id=uid and version=p_version returning * into r;
 if not found then raise exception '无权编辑，或资源已发生变化，请刷新后重试'; end if;
 return r;
end $$;
create or replace function public.hazama_set_category(p_id uuid,p_version integer,p_category text)
returns public.resources language plpgsql security definer set search_path='' as $$
declare r public.resources;
begin
 if auth.uid() is null or not public.hazama_is_admin() then raise exception '只有管理员可以调整其他人的资源分类'; end if;
 update public.resources set category=p_category,version=version+1,updated_at=clock_timestamp() where id=p_id and version=p_version returning * into r;
 if not found then raise exception '资源已修改或删除，请刷新后重试'; end if;
 return r;
end $$;
revoke all on function public.hazama_create(jsonb),public.hazama_update(uuid,integer,jsonb),public.hazama_set_category(uuid,integer,text) from public,anon,authenticated;
grant execute on function public.hazama_create(jsonb),public.hazama_update(uuid,integer,jsonb),public.hazama_set_category(uuid,integer,text) to authenticated;
create or replace function public.hazama_version() returns integer language sql immutable set search_path='' as $$select 8$$;
notify pgrst,'reload schema';
commit;

-- v8 升级到 v9：保留账号、资源、分类及历史删除通知，可重复运行。
begin;
alter table public.resource_notifications add column if not exists kind text not null default 'deleted' check(kind in ('deleted','reminder'));
alter table public.resource_notifications add column if not exists issue text;
alter table public.resource_notifications add column if not exists sender_id uuid references auth.users(id) on delete set null;
alter table public.resource_notifications add column if not exists resolved_at timestamptz;
create index if not exists notifications_sender_date on public.resource_notifications(sender_id,created_at desc);
create index if not exists notifications_resource_date on public.resource_notifications(resource_id,created_at desc);
create or replace function public.hazama_send_reminder(p_id uuid,p_issue text,p_message text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare r public.resources; nid uuid; msg text;
begin
 if auth.uid() is null or not public.hazama_is_admin() then raise exception '只有管理员可以发送资源提醒'; end if;
 if p_issue is null or p_issue not in ('夸克链接失效','百度链接失效','其他链接失效','其他问题') then raise exception '请选择有效的问题类型'; end if;
 if length(coalesce(p_message,''))>400 then raise exception '补充说明不能超过 400 字'; end if;
 if p_issue='其他问题' and nullif(btrim(p_message),'') is null then raise exception '请填写问题说明'; end if;
 select * into r from public.resources where id=p_id for update;
 if not found then raise exception '资源已删除，请刷新'; end if;
 if r.owner_id is null then raise exception '该资源没有所属账号，无法发送提醒'; end if;
 if exists(select 1 from public.resource_notifications where resource_id=p_id and kind='reminder' and created_at>clock_timestamp()-interval '60 seconds') then raise exception '该资源刚收到提醒，请至少等待 60 秒再发送'; end if;
 msg:=p_issue||case when nullif(btrim(p_message),'') is null then '' else '：'||btrim(p_message) end;
 insert into public.resource_notifications(recipient_id,resource_id,resource_name,reason,kind,issue,sender_id)
 values(r.owner_id,r.id,r.name,msg,'reminder',p_issue,auth.uid()) returning id into nid;
 return nid;
end $$;
create or replace function public.hazama_resolve_reminder(p_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception '请先登录'; end if;
 update public.resource_notifications set resolved_at=coalesce(resolved_at,now()),read_at=coalesce(read_at,now()) where id=p_id and recipient_id=auth.uid() and kind='reminder';
 if not found then raise exception '提醒不存在或无权操作'; end if;
 return true;
end $$;
-- 管理员查看全部已发提醒和处理反馈；普通用户仍只能 SELECT 自己收到的通知。
create or replace function public.hazama_reminder_log(p_offset integer default 0,p_limit integer default 30)
returns setof public.resource_notifications language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.hazama_is_admin() then raise exception '只有管理员可以查看提醒记录'; end if;
 if p_offset is null or p_limit is null or p_offset<0 or p_limit<1 or p_limit>100 then raise exception '分页参数错误'; end if;
 return query select * from public.resource_notifications where kind='reminder' order by created_at desc,id desc offset p_offset limit p_limit;
end $$;
revoke all on function public.hazama_send_reminder(uuid,text,text),public.hazama_resolve_reminder(uuid),public.hazama_reminder_log(integer,integer) from public,anon,authenticated;
grant execute on function public.hazama_send_reminder(uuid,text,text),public.hazama_resolve_reminder(uuid),public.hazama_reminder_log(integer,integer) to authenticated;
create or replace function public.hazama_version() returns integer language sql immutable set search_path='' as $$select 9$$;
notify pgrst,'reload schema';
commit;
