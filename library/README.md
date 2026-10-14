# 先看这里：如果你已部署上一版

只需覆盖 index.html、auth.js、app.js、style.css（请一起上传，避免缓存混用）。
数据库表和云函数与 v5 兼容：已运行 v5 database.sql、02-admin.sql 并部署 library-admin 的，无需重复部署。
确认 Supabase 的 Confirm email 已关闭并保存。首次设置管理员与重置服务的步骤见下文。

本次改的是注册方式和界面，不会修复访问 Supabase 的网络超时。网页必须能连接 Supabase 才能注册、登录和保存资源。请求失败时不会假装注册成功或把账号仅存在本机。

# 狭间图书馆 · 简化账号版 v6

保留原来的樱花界面、粉色飘花、智能识别网盘文案和现有配置。
浏览不登录；注册／登录后分享资源。换手机或电脑，登录同一邮箱即可编辑自己的资源。
取消资源钥匙。密码交给 Supabase Auth 管理，资源表不保存密码、邮箱或密码哈希。

## 按顺序升级（不用买服务器）

### 1. 升级数据库

先在 Supabase 控制台备份现有 resources 数据，并留存旧源码包。
在项目 SQL Editor 新建查询，粘贴本包 database.sql 全部内容，点击 Run。
出现 Success 即可。它可以重复运行，不会清空资源；会停用旧钥匙接口。
此时旧资源暂时没有账号归属，仍然能看；第 4 步会交给你的账号。
SQL 升级后旧网页不能继续用钥匙写入，应接着上传新网页。

### 2. 关闭邮箱确认（必须）

Supabase → Authentication → Sign In / Providers → Email：
- 开启 Email 注册登录，允许新用户注册。
- 关闭 Confirm email，点击保存。
- 密码最少长度设为 8；如需用 12345678 重置，不要设置必须包含字母、符号等冲突规则。
- 不启用 Anonymous sign-ins。不需要配置 SMTP、邮件模板或验证码。

邮箱在本版中是登录账号，没有验证邮箱归属；人工重置时请通过你与本人已有的联系方式核实身份。
以前开启验证时创建的待确认账号可能仍需管理员处理：请在 Supabase 的 Authentication → Users 检查该账号状态。不要删除已经绑定资源的账号。

### 3. 上传完整网页

把 index.html、app.js、auth.js、style.css、config.js、supabase.js、sakura-tree.png、sakura-petal.png 覆盖上传到原来 index.html 所在的 GitHub 文件夹。
新增的 auth.js 不能漏。建议将本包所有文件保持目录结构上传；SQL 和云函数源码不包含私密凭证，可以保留，但不能在网页里执行 SQL。
已有 config.js 的公开 anon key 和项目 URL 已保留。不用创建新项目，不用重新下载配置。
不要再额外套 library 文件夹，避免正式网址改变。
等 GitHub Pages 更新，强制刷新网页（电脑 Ctrl+F5，手机关闭旧标签后重新打开）。
用正式 HTTPS 网址测试，不要双击本地 index.html 作为日常入口。

### 4. 设置你为管理员，并接管旧资源

先在新网页注册你自己的邮箱。请先完成第 2 步关闭邮箱确认。
打开本包 02-admin.sql，把“请改成你自己注册的邮箱”改成你刚注册的邮箱。
复制全部内容到 SQL Editor 运行。这个操作把所有尚无 owner_id 的旧资源交给你；已经有账号归属的资源不受影响。
如果旧资源并非全由你管理，请先删去脚本里的 update 行，随后由你核实后在数据库逐条指定 owner_id。
回到网页退出重登，会看到“管理后台”；旧资源应出现编辑按钮。
管理员只能删除别人的资源，不能冒充作者编辑；普通用户只能修改、删除自己的。
没有任何“第一个注册的人自动成为管理员”的逻辑。

### 5. 开启管理员人工重置（一次部署）

这个小云函数运行在 Supabase，不需要你购买服务器。

1. 打开 Supabase 项目的 Edge Functions，选择新建／Deploy a new function，使用网页编辑器。
2. 函数名称必须为 library-admin。
3. 将 supabase/functions/library-admin/index.ts 全部复制到编辑器的 index.ts，部署。
4. 在该函数设置中，将网关 Verify JWT / Enforce JWT verification 关闭，再保存／部署。本函数内部仍会通过 auth.getUser 校验登录身份，并从数据库检查管理员名单，非管理员无法调用。
5. SUPABASE_URL、SUPABASE_ANON_KEY、SUPABASE_SERVICE_ROLE_KEY 是 Supabase 托管函数的内置环境变量。不要复制到 config.js、GitHub 或前端。
6. 默认仅允许 https://xiangcynthia6.github.io 来源。若网站域名变了，在 Edge Functions Secrets 设置 ALLOWED_ORIGIN 为新网址的 origin（例如 https://你的用户名.github.io，不带 /library 路径）。

如果你的控制台没有网页编辑器，也可在装好 Supabase CLI 的电脑中，在本包目录执行：

```sh
supabase login
supabase link --project-ref 你的项目编号
supabase functions deploy library-admin --no-verify-jwt
```

项目编号是 Project URL 中 https:// 与 .supabase.co 之间的部分。

以后你登录网站 → 管理后台 → 找到邮箱 → 重置密码 → 复制临时密码 → 确认重置。
请先确认申请人身份，再私下把临时密码告诉本人，让对方登录“我的账号”修改。
普通用户看不到此入口，即使自己构造请求，服务端也会拒绝。
管理员不能查看用户原密码，也不会替未验证邮箱自动完成验证。
旧版遗留待确认账号请先由项目主人核实归属并处理确认状态。

## 升级后检查

- 未登录可以查看全部公开资源，点分享会打开登录窗口。
- A 账号发布，刷新、退出重登后仍能编辑；另一台设备登录 A 也能编辑。
- B 账号不能编辑／删除 A 的资源；相同密码也不会混淆归属，权限绑定账号 ID。
- 旧钥匙链接不再赋予编辑权；旧本地钥匙备份不再需要。
- A 忘记密码后由管理员重置为 12345678（或另设临时密码），A 登录后在“我的账号”填写当前密码与新密码，资源归属不变。
- 只有你指定的管理员能列出账号并重置密码。
- 旧资源运行 02-admin.sql 后归到你名下。
- 管理入口报“服务未就绪”：检查函数名、部署、JWT 设置和管理员脚本。403 则检查管理员身份和允许的来源域名。
- 注册提示需要邮箱确认：确认 Confirm email 已关闭并保存。
- 新网页打开报权限函数失败：重新运行本包 database.sql；不要运行旧版 SQL。

前端在浏览器保存登录会话以维持登录，不保存用户输入的明文密码。公共电脑使用后请退出登录。
本版没有验证码或邮件找回功能。默认临时密码只在管理员点击确认重置后生效，不是任何账号的通用登录密码。用户改密为手动操作，本版没有强制改密限制。

## 已验证与尚待现场验证

本包提供可运行源码、SQL 和云函数；没有代替你操作远程 Supabase 或 GitHub。
本地数据库权限和前端交互测试结果见 验证说明.txt。真实注册登录与 Edge Functions 托管部署需配置后验证。

官方参考：
- https://supabase.com/docs/guides/auth/passwords
- https://supabase.com/docs/reference/javascript/auth-admin-updateuserbyid
- https://supabase.com/docs/guides/functions/deploy
