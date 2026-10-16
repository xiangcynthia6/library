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
