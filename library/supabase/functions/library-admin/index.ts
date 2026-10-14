// 只部署在 Supabase Edge Functions，绝不能把 service_role key 写入前端。
import { createClient } from 'npm:@supabase/supabase-js@2.49.8';
const url=Deno.env.get('SUPABASE_URL')!;
const anon=Deno.env.get('SUPABASE_ANON_KEY')!;
const secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const allowedOrigin=Deno.env.get('ALLOWED_ORIGIN')||'https://xiangcynthia6.github.io';
Deno.serve(async(req:Request)=>{
 const origin=req.headers.get('Origin');
 const headers={'Content-Type':'application/json','Access-Control-Allow-Origin':allowedOrigin,'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin','Cache-Control':'no-store'};
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 if(origin&&origin!==allowedOrigin)return reply({error:'来源不允许'},403);
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply({error:'仅支持 POST'},405);
 try{
  const authorization=req.headers.get('Authorization')||'';
  if(!authorization.startsWith('Bearer '))return reply({error:'请先登录'},401);
  const token=authorization.slice(7);
  const publicClient=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false}});
  // 即使关闭网关 JWT 检查，这里仍向 Auth 服务校验真实用户，不能跳过。
  const {data:auth,error:authError}=await publicClient.auth.getUser(token);
  if(authError||!auth.user)return reply({error:'登录已失效，请重新登录'},401);
  const service=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:role,error:roleError}=await service.from('library_admins').select('user_id').eq('user_id',auth.user.id).maybeSingle();
  if(roleError||!role)return reply({error:'只有网站管理员可以操作'},403);
  const body=await req.json();
  if(body.action==='list'){
   const page=Number(body.page||1);if(!Number.isInteger(page)||page<1||page>100000)return reply({error:'页码错误'},400);
   const {data,error}=await service.auth.admin.listUsers({page,perPage:50});if(error)throw error;
   return reply({users:data.users.map(u=>({id:u.id,email:u.email||'',created_at:u.created_at})),hasMore:data.users.length===50});
  }
  if(body.action==='reset'){
   if(typeof body.user_id!=='string'||typeof body.email!=='string'||typeof body.password!=='string')return reply({error:'重置信息不完整'},400);
   if(body.password.length<8||new TextEncoder().encode(body.password).length>72)return reply({error:'密码至少 8 位且不超过 72 字节'},400);
   const {data:target,error:targetError}=await service.auth.admin.getUserById(body.user_id);
   if(targetError||!target.user?.email||target.user.email.toLowerCase()!==body.email.toLowerCase())return reply({error:'目标账号不匹配，请刷新后重试'},400);
   const {error}=await service.auth.admin.updateUserById(body.user_id,{password:body.password});
   if(error)throw error;
   return reply({ok:true});
  }
  return reply({error:'不支持的操作'},400);
 }catch(e){
  // 不打印请求体、口令或管理密钥。
  return reply({error:e instanceof SyntaxError?'请求格式错误':'操作失败，请检查账号状态、密码规则和云函数配置'},400);
 }
});
