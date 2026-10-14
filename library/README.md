# 狭间图书馆 · 邮箱账号版 v5

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

### 2. 开启邮箱账号

在 Authentication 设置中找到 Email（通常在 Sign In / Providers），开启 Email 注册与登录，允许新用户注册。
不要启用 Anonymous sign-ins。密码最少长度设置为 8 或更高（网页最低为 8）。
推荐开启 Confirm email，并先按下文“配置邮件”完成 SMTP 和模板。

如果现在只想先用“邮箱＋密码，忘记后找你人工重置”，可以暂时关闭 Confirm email；此时注册不发邮件，但邮箱尚未验证，不能仅凭对方说出的邮箱就重置。
后续配置好 SMTP 后，再启用邮箱验证。关闭验证不会让找回密码自动免除 SMTP 配置。
如果启用了 Secure password change，长时间未认证可能要求额外 reauthentication nonce。本版账号内改密会先用当前密码重新登录；如服务仍要求 nonce，请重新登录后重试，或走忘记密码流程。

Authentication → URL Configuration：
- Site URL 填你的正式网页地址，目前是 https://xiangcynthia6.github.io/library/library/index.html
- Redirect URLs 也添加这一完整地址。
- 地址变了，同时修改 config.js 的 publicUrl；不要用 file:/// 本地地址。

### 3. 上传完整网页

把 index.html、app.js、auth.js、style.css、config.js、supabase.js、sakura-tree.png、sakura-petal.png 覆盖上传到原来 index.html 所在的 GitHub 文件夹。
新增的 auth.js 不能漏。建议将本包所有文件保持目录结构上传；SQL 和云函数源码不包含私密凭证，可以保留，但不能在网页里执行 SQL。
已有 config.js 的公开 anon key 和项目 URL 已保留。不用创建新项目，不用重新下载配置。
不要再额外套 library 文件夹，避免正式网址改变。
等 GitHub Pages 更新，强制刷新网页（电脑 Ctrl+F5，手机关闭旧标签后重新打开）。
用正式 HTTPS 网址测试，不要双击本地 index.html 作为日常入口。

### 4. 设置你为管理员，并接管旧资源

先在新网页注册你自己的邮箱。如果开启邮箱确认，请完成验证。
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
如果用户邮箱未验证，重置后仍需要先完成邮箱验证；不要为了方便替陌生人验证邮箱。

## 配置邮件：让用户自己找回密码

Supabase 默认邮件服务只向项目团队授权的地址发送测试邮件，不能当成面向访客的正常邮件服务。
正式向 QQ、网易、Gmail 等地址发验证码，需要配置自定义 SMTP。

1. 选择支持 SMTP 的发信服务，取得 Host、Port、Username、Password、Sender email；按服务商要求验证发信域名及 SPF / DKIM 等记录。
2. Supabase → Authentication → Email / SMTP Settings，开启 Custom SMTP，把服务商给你的信息填入，保存。密码是服务商的 SMTP 凭证，不是填到网页里的用户密码。
3. Authentication → Email Templates → Reset password：将正文替换为 email-templates/reset-password.html 的内容，主题可填“狭间图书馆密码重置验证码”。
4. Confirm signup：正文替换为 email-templates/confirm-signup.html，主题可填“狭间图书馆注册验证码”。保留 {{ .Token }} 原样，不能改成真实数字。
5. 到邮件／Auth 限速设置中检查发信额度和发送间隔，建议保持服务端限速。网页重发最少等待 60 秒，实际服务端可设置更长；验证码有效期由 Supabase 配置决定。
6. 用你自己控制的 QQ、163/126 和 Gmail 邮箱分别注册，退出，点击“忘记密码”，确认能收码、设置新密码、登录后管理原资源。

代码支持这些邮箱地址，但邮箱服务商可能拒收、延迟或放进垃圾箱；无法承诺任何提供商 100% 送达。邮件服务可能有自己的免费额度或费用，与静态网页无关。
如果暂时不配 SMTP，先用邮箱密码账号和管理员人工重置即可（注册邮箱确认需要相应调整，见第 2 步）。

## 升级后检查

- 未登录可以查看全部公开资源，点分享会打开登录窗口。
- A 账号发布，刷新、退出重登后仍能编辑；另一台设备登录 A 也能编辑。
- B 账号不能编辑／删除 A 的资源；相同密码也不会混淆归属，权限绑定账号 ID。
- 旧钥匙链接不再赋予编辑权；旧本地钥匙备份不再需要。
- A 忘记密码后通过邮件验证码设置新密码，资源归属不变。
- 只有你指定的管理员能列出账号并重置密码。
- 旧资源运行 02-admin.sql 后归到你名下。
- 管理入口报“服务未就绪”：检查函数名、部署、JWT 设置和管理员脚本。403 则检查管理员身份和允许的来源域名。
- 注册收不到邮件：检查 SMTP、邮件模板、Auth 日志、服务商日志、垃圾箱及限速。
- 新网页打开报权限函数失败：重新运行本包 database.sql；不要运行旧版 SQL。

前端在浏览器保存登录会话以维持登录，不保存用户输入的明文密码。公共电脑使用后请退出登录。
本版恢复链接兼容 Supabase 的 PASSWORD_RECOVERY 事件；推荐使用包内验证码模板，无需跨设备搬运编辑钥匙。

## 已验证与尚待现场验证

本包提供可运行源码、SQL 和云函数；没有代替你操作远程 Supabase 或 GitHub。
本地数据库权限和前端交互测试结果见 验证说明.txt。真实邮件送达与 Edge Functions 托管部署需配置后验证。

官方参考：
- https://supabase.com/docs/guides/auth/passwords
- https://supabase.com/docs/guides/auth/auth-smtp
- https://supabase.com/docs/guides/auth/auth-email-templates
- https://supabase.com/docs/reference/javascript/auth-admin-updateuserbyid
- https://supabase.com/docs/guides/functions/deploy
