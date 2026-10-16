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
