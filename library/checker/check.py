"""只读网盘分享，不下载或转存。Supabase 密钥仅用于数据库请求。"""
import os, re, json, time
from urllib.parse import urlsplit, parse_qs
from urllib.request import Request, urlopen
from datetime import datetime, timezone, timedelta

INVALID = ('分享的文件已经被取消','分享已取消','分享已过期','分享的文件已被删除','分享链接已失效','分享已失效','分享不存在','分享已被取消')

def extract_code(row, field):
    value=(row.get(field+'_code') or '').strip()
    if value: return value
    query=parse_qs(urlsplit(row.get(field) or '').query)
    for key in ('pwd','password','passcode'):
        if query.get(key): return query[key][0]
    # 多链接备注中的密码归属不明时不猜测。
    if sum(bool(row.get(k)) for k in ('baidu','quark','other'))==1:
        m=re.search(r'(?:提取码|访问码|提取密码|密码)\s*[：:=是为\s]*([a-zA-Z0-9]{4,12})(?![a-zA-Z0-9])',row.get('notes') or '')
        if m:return m[1]
    return ''

def combine(results):
    if any(s=='valid' for s,_ in results): return next(x for x in results if x[0]=='valid')
    if results and all(s=='invalid' for s,_ in results): return ('invalid','所有已填写的分享链接均明确失效')
    return ('unknown','；'.join(dict.fromkeys(reason for _,reason in results))[:300] or '没有可检测的链接')

def file_list(data):
    return isinstance(data,list) and bool(data) and all(isinstance(x,dict) and ('fs_id' in x or 'fid' in x) and ('server_filename' in x or 'file_name' in x) for x in data)

def baidu(browser,url,code):
    context=browser.new_context(locale='zh-CN',accept_downloads=False)
    page=context.new_page(); evidence=[]
    def response(resp):
        u=urlsplit(resp.url)
        if u.hostname=='pan.baidu.com' and u.path in ('/share/list','/api/shorturlinfo'):
            try:
                d=resp.json()
                if d.get('errno')==0 and file_list(d.get('list')): evidence.append(True)
            except Exception:pass
    page.on('response',response)
    try:
        page.goto(url,wait_until='domcontentloaded',timeout=25000)
        submitted=False
        for _ in range(14):
            page.wait_for_timeout(1000)
            if urlsplit(page.url).hostname!='pan.baidu.com':return ('unknown','百度页面跳转到登录或验证页')
            if evidence:return ('valid','百度：已读取分享文件列表')
            # 兼容文件列表直接内嵌在页面的数据；不把 HTTP 200 当成有效。
            files=page.evaluate('''() => {const d=window.yunData;const a=d ? (d.FILEINFO || d.file_list || d.FILE_LIST) : null;if(a)return a;try{return window.locals?.get('file_list')||[]}catch{return []}}''')
            if file_list(files):return ('valid','百度：已读取分享文件列表')
            body=page.locator('body').inner_text(timeout=3000)
            if any(x in body for x in INVALID):return ('invalid','百度明确提示分享取消、过期或删除')
            if '提取码错误' in body or '提取码不正确' in body:return ('unknown','百度提取码不正确，请修正后重检')
            inputs=page.locator('input[placeholder*="提取码"]:visible, input#accessCode:visible, .pickpw input[type="text"]:visible')
            if not submitted and inputs.count():
                if not code:return ('unknown','百度需要提取码，资源中未找到')
                inputs.first.fill(code)
                submit=page.locator('button:visible, a:visible, input[type="submit"]:visible').filter(has_text=re.compile(r'提取文件|提取|访问文件'))
                if submit.count(): submit.first.click(timeout=5000)
                else:inputs.first.press('Enter')
                submitted=True
        return ('unknown','百度未返回可确认的文件列表（可能需要验证码或登录）')
    finally:context.close()

def quark(browser,url,code):
    m=re.fullmatch(r'/s/([A-Za-z0-9]+)/*',urlsplit(url).path)
    if not m:return ('unknown','夸克分享地址格式暂不支持')
    context=browser.new_context(); request=context.request
    base='https://drive-pc.quark.cn/1/clouddrive/share/sharepage/'
    try:
        r=request.post(base+'token?pr=ucpro&fr=pc',data={'pwd_id':m[1],'passcode':code},timeout=20000)
        d=r.json(); token=(d.get('data') or {}).get('stoken')
        if not token:
            message=str(d.get('message') or d.get('msg') or '')
            if any(x in message for x in INVALID):return ('invalid','夸克明确提示分享失效')
            return ('unknown','夸克未获得访问令牌，可能是提取码或平台验证限制')
        d=request.get(base+'detail',params={'pr':'ucpro','fr':'pc','pwd_id':m[1],'stoken':token,'pdir_fid':'0','_page':'1','_size':'20'},timeout=20000).json()
        if d.get('code')==0 and file_list((d.get('data') or {}).get('list')):return ('valid','夸克：已读取分享文件列表')
        return ('unknown','夸克未返回可确认的文件列表')
    finally:context.close()

def check_one(browser,row):
    results=[]
    for field in ('baidu','quark','other'):
        url=(row.get(field) or '').strip()
        if not url:continue
        try:
            u=urlsplit(url)
            supported=u.scheme in ('http','https') and not u.username and not u.password and u.port in (None,80,443)
        except ValueError:supported=False
        if not supported:
            results.append(('unknown','地址格式不支持'));continue
        # 按真实域名识别，放在“其他链接”字段的百度分享也能检查。
        fn=baidu if u.hostname=='pan.baidu.com' else quark if u.hostname=='pan.quark.cn' else None
        if fn is None:results.append(('unknown','该站点暂不支持自动检测，可由管理员核验'));continue
        result=('unknown','网络访问失败，等待重试')
        for attempt in range(2):
            try:result=fn(browser,url,extract_code(row,field))
            except Exception:result=('unknown','网络超时或平台响应异常，等待重试')
            if result[0]!='unknown':break
            if attempt==0:time.sleep(3)
        results.append(result)
        if result[0]=='valid':break
    return combine(results)

def db(path,payload=None):
    base=os.environ['SUPABASE_URL'].rstrip('/')
    if not re.fullmatch(r'https://[a-z0-9-]+\.supabase\.co',base):raise RuntimeError('SUPABASE_URL 格式错误')
    key=os.environ['SUPABASE_SERVICE_ROLE_KEY']
    req=Request(base+'/rest/v1/'+path,data=None if payload is None else json.dumps(payload).encode(),headers={'apikey':key,'Authorization':'Bearer '+key,'Content-Type':'application/json'})
    with urlopen(req,timeout=30) as r:return json.load(r)

def main():
    from playwright.sync_api import sync_playwright
    rows=[];offset=0
    while True:
        part=db('resources?select=id,version,check_revision,baidu,quark,other,baidu_code,quark_code,notes,checked_at,check_source,check_status&order=id&limit=500&offset='+str(offset))
        rows.extend(part)
        if len(part)<500:break
        offset+=500
    cutoff=datetime.now(timezone.utc)-timedelta(days=7)
    # 手工核验保留到管理员选择“重新自动检测”或资源链接改动。
    rows=[r for r in rows if r.get('check_source')!='manual' and (os.getenv('FORCE_CHECK')=='true' or not r.get('checked_at') or datetime.fromisoformat(r['checked_at'].replace('Z','+00:00'))<(datetime.now(timezone.utc)-timedelta(hours=20) if r.get('check_status')=='unknown' else cutoff))]
    rows.sort(key=lambda r:r.get('checked_at') or '')
    counts={'valid':0,'invalid':0,'unknown':0,'stale':0}
    with sync_playwright() as p:
        browser=p.chromium.launch()
        try:
            for row in rows[:80]:
                try:status,reason=check_one(browser,row)
                except Exception:status,reason='unknown','地址解析失败，请管理员核验'
                saved=db('rpc/hazama_check_result',{'p_id':row['id'],'p_version':row['version'],'p_revision':row['check_revision'],'p_status':status,'p_reason':reason})
                counts[status if saved else 'stale']+=1
                print('检测进度',sum(counts.values()),'/',min(len(rows),80),flush=True)
                time.sleep(2)
        finally:browser.close()
    print('结果汇总',counts,'剩余排队',max(0,len(rows)-80))
if __name__=='__main__':main()
