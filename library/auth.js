 'use strict';
(()=>{
 const q=s=>document.querySelector(s);
 let client,user=null,admin=false,mode='login',busy=false,epoch=0,adminPage=1;
 document.body.insertAdjacentHTML('beforeend',`<dialog id="authDialog"><div class="dialog-head"><h2 id="authTitle">登录</h2><button type="button" class="close" data-close="authDialog" aria-label="关闭">×</button></div><p id="authHint" class="muted"></p><form id="authForm"><label id="emailLabel">邮箱<input id="authEmail" type="email" autocomplete="email" maxlength="254"></label><label id="oldPasswordLabel" hidden>当前密码<input id="authOldPassword" type="password" autocomplete="current-password"></label><label id="passwordLabel">密码<input id="authPassword" type="password" maxlength="72" autocomplete="current-password"></label><label id="repeatLabel" hidden>再次输入密码<input id="authRepeat" type="password" maxlength="72" autocomplete="new-password"></label><p id="authStatus" class="error" role="status"></p><button id="authSubmit" class="primary" type="submit">登录</button></form><div class="auth-links"><button id="authSignup" type="button" class="quiet">注册账号</button><button id="authForgot" type="button" class="quiet">忘记密码</button><button id="authBack" type="button" class="quiet">返回登录</button><button id="authLogout" type="button" class="quiet">退出登录</button></div></dialog><dialog id="adminDialog"><div class="dialog-head"><h2>账号管理</h2><button class="close" data-close="adminDialog" aria-label="关闭">×</button></div><p class="muted">核实申请人身份后重置密码。默认临时密码为 12345678，也可以修改或随机生成。请私下通知本人登录后修改。</p><button id="adminRefresh" class="secondary">刷新账号</button><p id="adminStatus" role="status"></p><div id="adminUsers"></div><div class="dialog-actions"><button id="adminPrev" class="secondary">上一页</button><span id="adminPage"></span><button id="adminNext" class="secondary">下一页</button></div><form id="adminResetForm" hidden><label>重置对象<input id="adminTargetEmail" readonly></label><label>临时密码<input id="adminNewPassword" type="text" autocomplete="off" minlength="8" maxlength="72" required></label><div class="dialog-actions"><button id="adminGenerate" type="button" class="secondary">生成随机密码</button><button id="adminReset" type="submit" class="primary">确认重置此账号</button></div></form></dialog>`);
 function message(s){q('#authStatus').textContent=s;}
 function errorText(e){const m=e?.message||'';if(/Invalid login credentials/i.test(m))return '邮箱或密码不正确。';if(/Email not confirmed/i.test(m))return '此账号还处于旧版待确认状态，请联系管理员处理。';if(/already registered/i.test(m))return '该邮箱已注册，请返回登录；忘记密码请联系管理员。';if(/rate limit|too many|security purposes/i.test(m))return '操作太频繁，请稍后重试。';if(/fetch|network|timeout|abort/i.test(m))return '无法连接账号服务器。请检查网络后再试；这与邮箱验证无关。若刚提交注册，请先尝试登录，避免重复注册。';return m||'操作失败，请稍后重试。';}
 function open(next='login'){
  if(busy)return;mode=next;message('');q('#authForm').reset();
  const account=mode==='account',forgot=mode==='forgot',signup=mode==='signup';
  q('#authTitle').textContent=account?'我的账号':forgot?'联系管理员找回密码':signup?'注册图书馆账号':'欢迎回到狭间';
  q('#authHint').textContent=account?`当前账号：${user?.email||''}。在这里修改登录密码。`:forgot?'请联系网站管理员，提供你的注册邮箱并核实身份。管理员重置后，用临时密码登录，再进入“我的账号”设置新密码。':signup?'填写邮箱和密码即可注册，无需邮箱验证码。请记住你的账号。':'登录后，可在电脑和手机上管理自己分享的资源。';
  q('#authForm').hidden=forgot;q('#emailLabel').hidden=account;q('#authEmail').required=!account&&!forgot;
  q('#oldPasswordLabel').hidden=!account;q('#authOldPassword').required=account;
  q('#repeatLabel').hidden=!(account||signup);q('#authRepeat').required=account||signup;
  q('#authPassword').required=!forgot;q('#authPassword').minLength=mode==='login'?1:8;q('#authPassword').autocomplete=mode==='login'?'current-password':'new-password';
  q('#authSubmit').textContent=account?'保存新密码':signup?'注册并登录':'登录';
  q('#authSignup').hidden=mode!=='login';q('#authForgot').hidden=mode!=='login';q('#authBack').hidden=mode==='login'||account;q('#authLogout').hidden=!account;
  if(!q('#authDialog').open)q('#authDialog').showModal();
 }
 async function checked(p){const r=await p;if(r.error)throw r.error;return r.data;}
 async function sync(session){const ticket=++epoch;user=session?.user||null;admin=false;const r=user?await client.rpc('hazama_is_admin'):{data:false};if(ticket!==epoch)return;admin=r.data===true;q('#accountOpen').textContent=user?'我的账号':'登录 / 注册';q('#accountOpen').title=user?.email||'';q('#adminOpen').hidden=!admin;if(!admin){q('#adminDialog').close();q('#adminUsers').replaceChildren();q('#adminResetForm').reset();q('#adminResetForm').hidden=true;}window.dispatchEvent(new CustomEvent('hazama-auth',{detail:{user,admin}}));}
 async function run(fn){if(busy)return;busy=true;q('#authSubmit').disabled=true;message('正在处理…');try{if(!client)throw Error('请先配置数据库连接。');await fn();}catch(e){message(errorText(e));}finally{busy=false;q('#authSubmit').disabled=false;}}
 q('#authForm').onsubmit=e=>{e.preventDefault();run(async()=>{
  const email=q('#authEmail').value.trim(),password=q('#authPassword').value;
  if(mode==='signup'||mode==='account'){if(password.length<8||new TextEncoder().encode(password).length>72)throw Error('密码至少 8 位，且 UTF-8 编码不超过 72 字节。');if(password!==q('#authRepeat').value)throw Error('两次输入的密码不一致。');}
  if(mode==='login'||mode==='signup'){
   const data=await checked(mode==='signup'?client.auth.signUp({email,password}):client.auth.signInWithPassword({email,password}));
   if(!data.session)throw Error('后台仍要求邮箱确认。请网站主人关闭 Supabase 的 Confirm email 并保存；本版不提供验证码流程。');
   await sync(data.session);q('#authDialog').close();
  }else if(mode==='account'){
   await checked(client.auth.signInWithPassword({email:user.email,password:q('#authOldPassword').value}));await checked(client.auth.updateUser({password}));q('#authForm').reset();message('密码已修改，下次请使用新密码登录。');
  }
 });};
 q('#authSignup').onclick=()=>open('signup');q('#authForgot').onclick=()=>open('forgot');q('#authBack').onclick=()=>open('login');
 q('#authLogout').onclick=()=>run(async()=>{await checked(client.auth.signOut());await sync(null);q('#authDialog').close();});
 q('#authDialog').addEventListener('close',()=>q('#authForm').reset());
 q('#accountOpen').onclick=q('#accountBottom').onclick=()=>open(user?'account':'login');
 let selected=null,adminBusy=false;
 async function adminCall(body){const {data,error}=await client.functions.invoke('library-admin',{body});if(error){let detail='';try{detail=(await error.context.json()).error||'';}catch{}throw Error(detail||'管理服务未就绪或权限不足。请按部署说明发布 library-admin 云函数。');}if(data?.error)throw Error(data.error);return data;}
 async function loadUsers(){if(adminBusy)return;adminBusy=true;q('#adminStatus').textContent='正在加载…';try{const data=await adminCall({action:'list',page:adminPage});if(!admin)return;q('#adminUsers').replaceChildren();selected=null;q('#adminResetForm').hidden=true;q('#adminResetForm').reset();for(const u of data.users){const row=document.createElement('div');row.className='admin-user';const label=document.createElement('span');label.textContent=u.email||'无邮箱账号';const b=document.createElement('button');b.className='secondary';b.textContent='重置密码';b.disabled=!u.email;b.onclick=()=>{selected=u;q('#adminTargetEmail').value=u.email;q('#adminResetForm').hidden=false;q('#adminNewPassword').value='12345678';};row.append(label,b);q('#adminUsers').append(row);}q('#adminPage').textContent=`第 ${adminPage} 页`;q('#adminPrev').disabled=adminPage<=1;q('#adminNext').disabled=!data.hasMore;q('#adminStatus').textContent='请选择需要协助的账号。';}catch(e){q('#adminStatus').textContent=errorText(e);}finally{adminBusy=false;}}
 function generate(){q('#adminNewPassword').value=Array.from(crypto.getRandomValues(new Uint8Array(16)),n=>n.toString(16).padStart(2,'0')).join('')+'Aa!';}
 q('#adminOpen').onclick=()=>{if(!admin)return;q('#adminDialog').showModal();loadUsers();};q('#adminRefresh').onclick=loadUsers;q('#adminPrev').onclick=()=>{if(adminBusy)return;adminPage=Math.max(1,adminPage-1);loadUsers();};q('#adminNext').onclick=()=>{if(adminBusy)return;adminPage++;loadUsers();};q('#adminGenerate').onclick=generate;
 q('#adminResetForm').onsubmit=async e=>{e.preventDefault();if(!selected||adminBusy)return;const target={...selected};if(!confirm(`确认已核实身份，并重置 ${target.email} 的密码？`))return;adminBusy=true;q('#adminReset').disabled=true;try{await adminCall({action:'reset',user_id:target.id,email:target.email,password:q('#adminNewPassword').value});q('#adminStatus').textContent=`已为 ${target.email} 重置密码。请私下告知本人，并请对方登录“我的账号”修改。`;}catch(e){q('#adminStatus').textContent=errorText(e);}finally{adminBusy=false;q('#adminReset').disabled=false;}};
 q('#adminDialog').addEventListener('close',()=>{q('#adminResetForm').reset();q('#adminResetForm').hidden=true;selected=null;});
 window.HazamaAuth={open,async init(c){client=c;c.auth.onAuthStateChange((_event,session)=>{setTimeout(()=>sync(session).catch(()=>{}),0);});const data=await checked(c.auth.getSession());await sync(data.session);}};
})();
