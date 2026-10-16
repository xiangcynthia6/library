-- 第二步：先在网页注册自己的邮箱，再在 Supabase SQL Editor 运行。
-- 将下面邮箱改成你自己的、确实已经注册的邮箱。
-- 此脚本会把所有旧版“没有账号归属”的资源交给该账号；不会更改已有账号归属。
-- 只在你确认旧资源都归你管理时运行。不是把管理员交给首个注册者。
begin;
do $$
declare admin_email text := '请改成你自己注册的邮箱'; uid uuid;
begin
 select id into uid from auth.users where lower(email)=lower(btrim(admin_email));
 if uid is null then raise exception '未找到该邮箱，请先注册，再修改脚本中的邮箱'; end if;
 insert into public.library_admins(user_id) values(uid) on conflict do nothing;
 update public.resources set owner_id=uid, updated_at=now(),version=version+1 where owner_id is null;
end $$;
commit;
