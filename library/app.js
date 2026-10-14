'use strict';
const $ = s => document.querySelector(s);
const fields = ['name','quark','baidu','other','quark_code','baidu_code','notes'];
const config = window.RESOURCE_CONFIG || {};
const live = !!(config.url && config.key);
let currentUser = null, isAdmin = false;
let client, rows = [], filter = 'all', page = 1, editing = null, busy = false, loading = false, queued = false, syncTimer, testedConfig = '';
function escapeHTML(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function validURL(s){try{const u=new URL(s);return ['http:','https:'].includes(u.protocol)&&!!u.hostname&&!u.username&&!u.password&&!/\s/.test(s);}catch{return false;}}
function toast(s){$('#toast').textContent=s;$('#toast').hidden=false;clearTimeout(toast.timer);toast.timer=setTimeout(()=>$('#toast').hidden=true,4200);}
function fail(e){return e?.message || '操作失败，请稍后重试';}
async function copy(s){try{await navigator.clipboard.writeText(s);toast('已复制');}catch{const t=document.createElement('textarea');t.value=s;document.body.append(t);t.select();let ok=false;try{ok=document.execCommand('copy');}catch{}t.remove();if(!ok)throw Error('复制未成功，请选中文字手动复制。');toast('已复制');}}
function download(name,content,type='application/json'){const u=URL.createObjectURL(new Blob([content],{type}));const a=document.createElement('a');a.href=u;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(u),2000);}
async function rpc(name,args){const {data,error}=await client.rpc(name,args);if(error)throw error;return data;}
function mine(r){return !!currentUser && r.owner_id === currentUser.id;}
function date(s){return new Date(s).toLocaleDateString('zh-CN',{year:'numeric',month:'2-digit',day:'2-digit'});}
function render(){
 $('#count').textContent=rows.length;
 const q=$('#search').value.trim().toLocaleLowerCase();
 let items=rows.filter(r=>(filter==='all'||(filter==='mine'?mine(r):!!r[filter]))&&(`${r.name} ${r.notes}`).toLocaleLowerCase().includes(q));
 const sort=$('#sort').value;items.sort((a,b)=>sort==='name'?a.name.localeCompare(b.name,'zh-CN'):sort==='old'?a.created_at.localeCompare(b.created_at):b.created_at.localeCompare(a.created_at));
 $('#resultCount').textContent=`${items.length} 份资源`;
 $('#loadMore').hidden=items.length<=page*18;
 if(!items.length){$('#list').innerHTML=`<div class="empty"><div class="empty-icon">▧</div><b>${rows.length?'没有找到匹配的资源':'好资源，从你的第一份分享开始'}</b><p>${rows.length?'试试其他关键词或分类。':'点击上方“分享资源”，把值得收藏的链接放在这里。'}</p></div>`;return;}
 $('#list').innerHTML=items.slice(0,page*18).map(r=>{
 const owned=mine(r);
 const links=[['quark','夸克网盘'],['baidu','百度网盘'],['other','其他链接']].filter(([k])=>r[k]&&validURL(r[k]));
 return `<article class="card"><div class="card-top"><span class="file-icon">▤</span>${owned?'<span class="mine-badge">我分享的</span>':''}</div><h3>${escapeHTML(r.name)}</h3><p class="description">${escapeHTML(r.notes||'暂无备注，打开链接查看内容。')}</p><div class="links">${links.map(([k,label])=>`<a class="link-button ${k}" href="${escapeHTML(r[k])}" target="_blank" rel="noopener noreferrer">${label} ↗</a><button class="copy-small" data-action="copy-${k}" data-id="${r.id}" aria-label="复制${label}链接">复制</button>`).join('')}</div>${['quark','baidu'].filter(k=>r[k]&&r[k+'_code']).map(k=>`<div class="code">${k==='quark'?'夸克':'百度'}提取码：${escapeHTML(r[k+'_code'])}<button class="copy-small" data-action="code-${k}" data-id="${r.id}">复制</button></div>`).join('')}<div class="card-footer"><span class="date">${date(r.created_at)} 分享${r.version>1?' · 已更新':''}</span>${owned?`<div class="actions"><button data-action="edit" data-id="${r.id}">编辑</button><button class="danger" data-action="delete" data-id="${r.id}">删除</button></div>`:isAdmin?`<div class="actions"><button class="danger" data-action="delete" data-id="${r.id}">管理员删除</button></div>`:'<span class="date">公开分享</span>'}</div></article>`;
 }).join('');
}
async function refresh(){
 if(loading){queued=true;return;}loading=true;
 try{
 if(live){if(!client)throw Error('数据库连接未初始化');let result=[],start=0;while(true){const {data,error}=await client.from('resources').select('*').order('created_at',{ascending:false}).order('id').range(start,start+499);if(error)throw error;result.push(...data);if(data.length<500)break;start+=500;if(start>=20000)throw Error('资源数量已超过当前版本加载上限，请升级分页查询。');}rows=result;}
 else rows=[];
 render();
 }catch(e){$('#connection').textContent='同步失败';toast('未能刷新：'+fail(e));}
 finally{loading=false;if(queued){queued=false;setTimeout(refresh,200);}}
}
function openEditor(r){
 if(!client){toast('请先完成数据库配置');return;}
 if(!currentUser){window.HazamaAuth.open('login');return;}
 if(r&&!mine(r)){toast('只能编辑自己上传的资源');return;}
 editing=r?{...r}:null;$('#resourceForm').reset();$('#smartShareText').value='';$('#smartPasteStatus').textContent='自动识别链接、提取码及资源名称';for(const f of fields)$('#resourceForm').elements[f].value=r?.[f]||'';$('#editorTitle').textContent=r?'编辑资源':'分享一份好资源';$('#saveResource').textContent=r?'保存修改':'提交资源';$('#formError').textContent='';$('#editor').showModal();
}
// 智能解析网盘分享文案；只填入可信 URL，避免把附带文字作为链接保存。
function parseShareText(text){
 const result={};
 const urlPattern=/https?:\/\/[^\s<>"'“”‘’。，；;、）)\]】]+/gi;
 const matches=[...text.matchAll(urlPattern)];
 for(let i=0;i<matches.length;i++){
  const match=matches[i],url=match[0].replace(/[.,!?，。！？；;：:]+$/g,'');
  if(!validURL(url))continue;
  let parsedUrl;try{parsedUrl=new URL(url);}catch{continue;}
  const host=parsedUrl.hostname.toLowerCase();
  const kind=host==='pan.quark.cn'?'quark':host==='pan.baidu.com'?'baidu':'other';
  if(result[kind])continue;
  result[kind]=url;
  if(kind==='other')continue;
  // 百度链接自带 ?pwd=xxxx 时，优先采用链接自身的提取码。
  // 不要让相邻的其他分享文本覆盖 URL 自带的密码。
  const embedded=parsedUrl.searchParams.get('pwd')||parsedUrl.searchParams.get('password');
  const after=text.slice(match.index+match[0].length,Math.min(text.length,match.index+match[0].length+160));
  const before=text.slice(Math.max(0,match.index-130),match.index);
  const codePattern=/(?:提取码|访问码|提取密码|访问密码|密码|code|pwd)\s*[：:=是为\s]*([a-zA-Z0-9]{4,12})/i;
  const afterCode=after.match(codePattern);
  const beforeCode=before.match(/(?:提取码|访问码|提取密码|访问密码|密码|code|pwd)\s*[：:=是为\s]*([a-zA-Z0-9]{4,12})\s*$/i);
  const code=embedded||afterCode?.[1]||beforeCode?.[1];
  if(code)result[kind+'_code']=code;
 }
 // 文件名称：优先明确字段，其次匹配夸克「分享了《标题》」和其他成对书名号。
 const named=text.match(/(?:分享的文件|分享文件|文件名称|文件名|资源名称|资源名|文件)[：:]\s*([^\r\n]+)/i);
 if(named){
  const candidate=named[1].replace(/(?:\s*链接[：:].*)$/,'').trim();
  if(candidate&&candidate.length<=120)result.name=candidate;
 }
 if(!result.name){
  // 夸克文案：我用夸克网盘给你分享了「《笼中雀》作者：...」
  // 只取内层书名号内容，不把「、作者信息或分享口令当成名称。
  const book=text.match(/《\s*([^《》\r\n]{1,120}?)\s*》/);
  if(book)result.name=book[1].trim();
 }
 if(!result.name){
  const quoted=[...text.matchAll(/[「【“]([^「」【】“”\r\n]{2,120})[」】”]/g)]
   .map(m=>m[1].trim())
   .filter(t=>!/(?:超级会员|会员|百度网盘APP|夸克网盘APP|复制这段内容|点击链接)/i.test(t));
  if(quoted.length)result.name=quoted[0];
 }

 return result;
}
function applyShareText(){
 const text=$('#smartShareText').value.trim(),status=$('#smartPasteStatus');
 if(!text){status.textContent='请先粘贴分享文字';return;}
 const parsed=parseShareText(text),form=$('#resourceForm');
 const found=['quark','baidu','other'].filter(k=>parsed[k]);
 if(!found.length){status.textContent='未找到有效的 http/https 链接，请检查粘贴内容';return;}
 for(const k of found){form.elements[k].value=parsed[k];if(parsed[k+'_code'])form.elements[k+'_code'].value=parsed[k+'_code'];}
 if(parsed.name&&!form.elements.name.value.trim())form.elements.name.value=parsed.name;
 status.textContent='已识别 '+found.map(k=>({quark:'夸克',baidu:'百度',other:'其他'})[k]).join('、')+'链接'+(found.some(k=>parsed[k+'_code'])?'及提取码':'')+' ✓';
 $('#formError').textContent='';
}
$('#smartParse').addEventListener('click',applyShareText);
let smartPasteDebounce;
$('#smartShareText').addEventListener('input',()=>{clearTimeout(smartPasteDebounce);smartPasteDebounce=setTimeout(applyShareText,250);});
// 兼容用户直接粘贴到旧的链接输入框；也支持纯链接。
for(const k of ['quark','baidu','other']){
 const input=$('#resourceForm').elements[k];
 input.addEventListener('paste',e=>{
  const pasted=e.clipboardData?.getData('text/plain')||'';
  if(!pasted||(!/\s/.test(pasted)&&validURL(pasted)))return;
  const parsed=parseShareText(pasted);
  if(!Object.keys(parsed).some(x=>['quark','baidu','other'].includes(x)))return;
  e.preventDefault();$('#smartShareText').value=pasted;applyShareText();
 });
}
$('#resourceForm').addEventListener('submit',async e=>{
 e.preventDefault();if(busy)return;const data={};for(const f of fields)data[f]=$('#resourceForm').elements[f].value.trim();
 if(!data.name){$('#formError').textContent='请填写资源名称';return;}
 if(!['quark','baidu','other'].some(k=>data[k])){$('#formError').textContent='请至少填写一个链接';return;}
 if(['quark','baidu','other'].some(k=>data[k]&&!validURL(data[k]))){$('#formError').textContent='请填写完整的 http:// 或 https:// 链接，不要附带提取码文字';return;}
 busy=true;$('#saveResource').disabled=true;$('#formError').textContent='';
 try{
 if(!currentUser)throw Error('登录已失效，请重新登录后提交');
 const result=editing?await rpc('hazama_update',{p_id:editing.id,p_version:editing.version,p_data:data}):await rpc('hazama_create',{p_data:data});
 const record=Array.isArray(result)?result[0]:result;if(!record?.id)throw Error('未收到保存结果，请先刷新列表确认');
 $('#editor').close();await refresh();toast(editing?'修改已保存':'资源已公开分享');

 }catch(err){$('#formError').textContent=fail(err);}
 finally{busy=false;$('#saveResource').disabled=false;}
});
$('#list').addEventListener('click',async e=>{const b=e.target.closest('button[data-action]');if(!b)return;const r=rows.find(x=>x.id===b.dataset.id);if(!r)return;const action=b.dataset.action;
 try{if(action.startsWith('copy-'))await copy(r[action.slice(5)]);else if(action.startsWith('code-'))await copy(r[action.slice(5)+'_code']);else if(action==='edit')openEditor(r);else if(action==='delete'){
 if(!confirm(`确定删除“${r.name}”？删除后无法撤销。`))return;b.disabled=true;
 await rpc('hazama_delete',{p_id:r.id,p_version:r.version});
 await refresh();toast('资源已删除');}}
 catch(err){toast(fail(err));b.disabled=false;}
});
$('#filters').addEventListener('click',e=>{const b=e.target.closest('[data-filter]');if(!b)return;filter=b.dataset.filter;page=1;document.querySelectorAll('[data-filter]').forEach(x=>x.classList.toggle('active',x===b));render();});
$('#search').addEventListener('input',()=>{page=1;render();});$('#sort').addEventListener('change',()=>{page=1;render();});$('#loadMore').onclick=()=>{page++;render();};
$('#add').onclick=()=>openEditor();$('#refresh').onclick=refresh;$('#helpOpen').onclick=()=>$('#help').showModal();$('#setupOpen').onclick=()=>{$('#configUrl').value=config.url||'';$('#configKey').value=config.key||'';$('#configTitle').value=config.title||'狭间图书馆';$('#setup').showModal();};
document.querySelectorAll('[data-close]').forEach(b=>b.onclick=()=>{if(b.dataset.close==='editor'&&busy)return;$('#'+b.dataset.close).close();});$('#editor').addEventListener('cancel',e=>{if(busy)e.preventDefault();});
function readConfig(){const url=$('#configUrl').value.trim().replace(/\/+$/,'');const key=$('#configKey').value.trim();if(!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url))throw Error('Project URL 应类似 https://xxxxxxxx.supabase.co');let payload;try{payload=JSON.parse(atob(key.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')));}catch{throw Error('请复制 Legacy API Keys 中的 anon（public）key。');}if(payload.role!=='anon')throw Error('只能填写公开 anon key，禁止使用管理密钥。');return {url,key,title:$('#configTitle').value.trim()||'狭间图书馆',publicUrl:'https://xiangcynthia6.github.io/library/library/index.html'};}
async function testConfiguration(){const c=readConfig();const temp=window.supabase.createClient(c.url,c.key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});const {error}=await temp.from('resources').select('id').limit(1);if(error)throw Error('无法读取资源表：请确认 database.sql 已运行，以及 URL、anon key 是否来自同一项目。');const check=await temp.rpc('hazama_version');if(check.error||check.data!==5)throw Error('权限函数检测失败，请重新运行完整 database.sql。');testedConfig=JSON.stringify(c);$('#configResult').textContent='✓ 连接与权限函数检测通过。下载 config.js，替换原文件并上传 GitHub。';return c;}
$('#testConfig').onclick=async()=>{$('#testConfig').disabled=true;$('#configResult').textContent='正在检测…';try{await testConfiguration();}catch(e){testedConfig='';$('#configResult').textContent=fail(e);}finally{$('#testConfig').disabled=false;}};
$('#downloadConfig').onclick=async()=>{$('#downloadConfig').disabled=true;try{const c=readConfig();if(testedConfig!==JSON.stringify(c))await testConfiguration();download('config.js','window.RESOURCE_CONFIG = '+JSON.stringify(c,null,2)+';\n','text/javascript');}catch(e){$('#configResult').textContent=fail(e);}finally{$('#downloadConfig').disabled=false;}};
document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh();});
window.addEventListener('hazama-auth',e=>{
 const changed=currentUser?.id!==e.detail.user?.id;currentUser=e.detail.user;isAdmin=e.detail.admin;
 if(changed&&$('#editor').open)$('#editor').close();render();
});
(async()=>{
 document.title=config.title||'狭间图书馆';$('#brandTitle').textContent=document.title;
 $('#modeBanner').textContent=live?'公开资源库 · 浏览无需登录，登录后可分享和管理自己的资源。':'尚未连接数据库 · 请通过“首次配置”连接项目，账号版不使用本机模拟登录。';
 if(location.hash.includes('edit=')||location.hash.includes('key=')){history.replaceState(null,'',location.pathname+location.search);toast('本网站已升级为账号登录，请使用邮箱和密码登录。');}
 if(live){try{
 if(!window.supabase)throw Error('supabase.js 未加载，请完整上传文件');
 client=window.supabase.createClient(config.url,config.key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
 await window.HazamaAuth.init(client);
 client.channel('resource-list').on('postgres_changes',{event:'*',schema:'public',table:'resources'},()=>{clearTimeout(syncTimer);syncTimer=setTimeout(refresh,200);}).subscribe(s=>{$('#connection').textContent=s==='SUBSCRIBED'?'实时连接':s==='CHANNEL_ERROR'||s==='TIMED_OUT'?'定时同步 · 15秒':'正在连接';});
 }catch(e){toast(fail(e));$('#modeBanner').textContent='连接失败：'+fail(e);}}
 else $('#connection').textContent='未配置';
 await refresh();if(live)setInterval(()=>{if(!document.hidden)refresh();},15000);
})();

// 花瓣由树冠位置出发；背景树使用独立 SVG 枝干动画。
(()=>{
 const layer=document.querySelector('#sakura'),toggle=document.querySelector('#petalToggle'),tree=document.querySelector('#sakuraTree');
 const motion=window.matchMedia?.('(prefers-reduced-motion: reduce)');
 let enabled=!motion?.matches;
 try{const pref=localStorage.getItem('hazama:petals');if(pref!==null)enabled=pref==='on'&&!motion?.matches;}catch{}
 const crowns=[[150,345,98,61],[215,258,107,75],[288,198,104,69],[468,160,105,70],[530,250,116,74],[613,320,106,67],[375,115,102,56],[367,233,126,74],[437,360,100,61]];
 const petals=[];
 for(let i=0;i<26;i++){
  const node=document.createElement('i');node.className='petal';
  const c=crowns[i%crowns.length],a=Math.random()*Math.PI*2,r=Math.sqrt(Math.random());
  petals.push({node,x:c[0]+Math.cos(a)*c[2]*r,y:c[1]+Math.sin(a)*c[3]*r});
  node.style.cssText=`--size:${7+Math.random()*7}px;--duration:${14+Math.random()*14}s;--delay:-${Math.random()*35}s;--rotation:${Math.random()*360}deg;--drift:${-100-Math.random()*300}px;`;
  layer.append(node);
 }
 function place(){const box=tree.getBoundingClientRect();for(const p of petals){p.node.style.left=(box.left+p.x/760*box.width)+'px';p.node.style.top=(box.top+p.y/900*box.height)+'px';}}
 function show(){layer.hidden=!enabled;toggle.textContent=enabled?'飘花：开':'飘花：关';toggle.setAttribute('aria-pressed',String(enabled));}
 toggle.onclick=()=>{enabled=!enabled;try{localStorage.setItem('hazama:petals',enabled?'on':'off');}catch{}show();};
 motion?.addEventListener?.('change',e=>{if(e.matches){enabled=false;show();}});
 window.addEventListener('resize',place);place();show();
})();
