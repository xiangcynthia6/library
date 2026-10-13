-- 拾光资源库 v1。整段粘贴到新 Supabase 项目的 SQL Editor，点击 Run。
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
create table if not exists resource_private.keys (
 resource_id uuid primary key references public.resources(id) on delete cascade,
 token_hash bytea not null
);
alter table public.resources enable row level security;
alter table resource_private.keys enable row level security;
revoke all on public.resources from public,anon,authenticated;
revoke all on resource_private.keys from public,anon,authenticated;
grant select on public.resources to anon,authenticated;
drop policy if exists resources_read on public.resources;
create policy resources_read on public.resources for select to anon,authenticated using(true);

-- 写入只走以下函数。search_path 固定，私密表不可直接读取。
create or replace function public.resource_create(p_data jsonb,p_token text)
returns public.resources language plpgsql security definer set search_path = '' as $$
declare r public.resources;
begin
 if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception '编辑钥匙格式错误'; end if;
 insert into public.resources(name,quark,baidu,other,quark_code,baidu_code,notes)
 values(btrim(p_data->>'name'),coalesce(p_data->>'quark',''),coalesce(p_data->>'baidu',''),coalesce(p_data->>'other',''),coalesce(p_data->>'quark_code',''),coalesce(p_data->>'baidu_code',''),coalesce(p_data->>'notes','')) returning * into r;
 insert into resource_private.keys(resource_id,token_hash) values(r.id,sha256(convert_to(p_token,'UTF8')));
 return r;
end $$;
create or replace function public.resource_verify(p_id uuid,p_token text)
returns boolean language sql security definer set search_path = '' as $$
 select exists(select 1 from resource_private.keys where resource_id=p_id and token_hash=sha256(convert_to(p_token,'UTF8')));
$$;
create or replace function public.resource_update(p_id uuid,p_token text,p_version integer,p_data jsonb)
returns public.resources language plpgsql security definer set search_path = '' as $$
declare r public.resources;
begin
 if not public.resource_verify(p_id,p_token) then raise exception '编辑钥匙无效或资源已删除'; end if;
 update public.resources set name=btrim(p_data->>'name'),quark=coalesce(p_data->>'quark',''),baidu=coalesce(p_data->>'baidu',''),other=coalesce(p_data->>'other',''),quark_code=coalesce(p_data->>'quark_code',''),baidu_code=coalesce(p_data->>'baidu_code',''),notes=coalesce(p_data->>'notes',''),updated_at=clock_timestamp(),version=version+1 where id=p_id and version=p_version returning * into r;
 if not found then raise exception '资源已被修改或删除，请刷新后重新编辑'; end if;
 return r;
end $$;
create or replace function public.resource_delete(p_id uuid,p_token text,p_version integer)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
 if not public.resource_verify(p_id,p_token) then raise exception '编辑钥匙无效或资源已删除'; end if;
 delete from public.resources where id=p_id and version=p_version;
 if not found then raise exception '资源已被修改或删除，请刷新后重试'; end if;
 return true;
end $$;
revoke all on function public.resource_create(jsonb,text) from public;
revoke all on function public.resource_verify(uuid,text) from public;
revoke all on function public.resource_update(uuid,text,integer,jsonb) from public;
revoke all on function public.resource_delete(uuid,text,integer) from public;
grant execute on function public.resource_create(jsonb,text),public.resource_verify(uuid,text),public.resource_update(uuid,text,integer,jsonb),public.resource_delete(uuid,text,integer) to anon,authenticated;
-- 仅公开资源表参加实时订阅，钥匙哈希不参加。
do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='resources') then
 alter publication supabase_realtime add table public.resources;
 end if;
end $$;
notify pgrst,'reload schema';
commit;
