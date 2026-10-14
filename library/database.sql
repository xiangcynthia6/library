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
