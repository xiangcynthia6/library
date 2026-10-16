begin;
alter table public.resources add column if not exists check_status text not null default 'unchecked' check(check_status in ('unchecked','valid','invalid','unknown'));
alter table public.resources add column if not exists check_reason text not null default '';
alter table public.resources add column if not exists checked_at timestamptz;
alter table public.resources add column if not exists check_source text;
alter table public.resources add column if not exists check_revision bigint not null default 0;
-- 链接、密码或备注改变时使旧结果失效；标题和分类不影响检测。
create or replace function resource_private.reset_validity() returns trigger language plpgsql set search_path='' as $$
begin
 if row(new.baidu,new.quark,new.other,new.baidu_code,new.quark_code,new.notes) is distinct from row(old.baidu,old.quark,old.other,old.baidu_code,old.quark_code,old.notes) then
 new.check_status:='unchecked';new.check_reason:='链接或提取码已更新，等待检测';new.checked_at:=null;new.check_source:=null;new.check_revision:=old.check_revision+1;
 end if;return new;
end $$;
drop trigger if exists reset_resource_validity on public.resources;
create trigger reset_resource_validity before update on public.resources for each row execute function resource_private.reset_validity();
-- 自动程序专用：版本和检测修订号同时匹配才写入，防止覆盖新链接或管理员刚做的核验。
create or replace function public.hazama_check_result(p_id uuid,p_version integer,p_revision bigint,p_status text,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if p_status is null or p_status not in ('valid','invalid','unknown') then raise exception '状态错误';end if;
 update public.resources set check_status=p_status,check_reason=left(coalesce(p_reason,''),300),checked_at=now(),check_source='auto',check_revision=check_revision+1 where id=p_id and version=p_version and check_revision=p_revision;
 return found;
end $$;
revoke all on function public.hazama_check_result(uuid,integer,bigint,text,text) from public,anon,authenticated;
grant execute on function public.hazama_check_result(uuid,integer,bigint,text,text) to service_role;
create or replace function public.hazama_manual_check(p_id uuid,p_version integer,p_status text,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.hazama_is_admin() then raise exception '只有管理员可以核验';end if;
 if p_status is null or p_status not in ('valid','invalid','unknown','unchecked') then raise exception '状态错误';end if;
 update public.resources set check_status=p_status,check_reason=left(coalesce(p_reason,''),300),checked_at=case when p_status='unchecked' then null else now() end,check_source=case when p_status='unchecked' then null else 'manual' end,check_revision=check_revision+1 where id=p_id and version=p_version;
 if not found then raise exception '资源已更新，请刷新后重试';end if;return true;
end $$;
revoke all on function public.hazama_manual_check(uuid,integer,text,text) from public,anon,authenticated;
grant execute on function public.hazama_manual_check(uuid,integer,text,text) to authenticated;
create or replace function public.hazama_version() returns integer language sql immutable set search_path='' as $$ select 10 $$;
notify pgrst,'reload schema';
commit;
