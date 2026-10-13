# v4 更新提示

已有用户：请先阅读「更新说明.txt」。本包保留现有连接，不必重新配置数据库。覆盖到 GitHub 原目录即可。

# 狭间图书馆 · GitHub Pages 版

## 先试用（不用配置）

解压压缩包，双击 `index.html`。可以试用提交、修改、删除、搜索、分类和钥匙备份。
顶部显示“本机体验模式”时，数据仅在当前浏览器，不与其他设备共享。
请使用 Edge / Chrome 等现代浏览器，并允许本地存储。如果本地文件不能保存数据，先将文件上传 Pages 再体验。

## 正式上线，只做一次

1. 打开 https://supabase.com/dashboard 注册账号。创建新项目（New project），记录自己设置的数据库密码，等待创建完成。
2. 进入 SQL Editor → New query，用记事本打开 `database.sql`，复制全部内容，粘贴并点击 Run。成功时通常提示 Success。可以重复运行，不清空资源。不用开启 Anonymous Sign-ins。
3. 打开 `index.html`，点右上角“首次配置”。
4. 将项目的 Project URL 与 **Legacy API Keys 里的 anon / public key** 填入对应位置。不是 service_role，不是 secret key，不是数据库密码。网页会拒绝管理密钥。
5. 点“检测连接”，成功后点“下载 config.js”。用下载的文件替换本文件夹中的同名文件。不要变成 config (1).js 或 config.js.txt。
6. 创建 GitHub 仓库；使用免费账户部署 Pages 时选择 Public。点 Add file → Upload files，上传解压后本目录的文件。确保 `index.html` 在仓库根目录，不要上传 ZIP，也不要再套一个文件夹。
7. 仓库 Settings → Pages → Source 选择 Deploy from a branch → main → /(root) → Save。等待部署后，打开 GitHub 给出的网页网址。不是仓库网址。
8. 再打开网页，顶部应显示“公开资源库”。发一条测试资源，用手机或另一个浏览器查看；在另一个浏览器中应无编辑按钮。复制该资源的专属编辑链接到另一浏览器，应能编辑这条资源。

把**普通网页网址**发给别人即可。访客无需登录或配置。只有站主需要 Supabase 账号。

## 重要操作

- 名称必填；夸克、百度、其他链接至少一个。提取码有单独的输入框，链接框只填 URL。
- 每条资源生成独立的 256 位随机编辑钥匙，浏览器保存原文；数据库在非公开 schema 保存 SHA-256 哈希。
- 拿到钥匙的人均可编辑、删除对应资源。因此不要公开发送编辑链接，也不要将钥匙备份上传到 GitHub。
- 编辑链接的钥匙放在 URL 的 `#` 后，打开后会从地址栏移除；网页使用 no-referrer。使用 HTTPS 正式网址分享编辑链接。本机体验模式的链接不能跨设备恢复数据。
- 清理浏览器、换浏览器、换设备前，备份钥匙。无钥匙无法证明原作者身份，也无法依靠 IP 找回。请勿使用无痕窗口保存重要钥匙。
- “备份我的钥匙”导出权限文件，不是资源数据备份；与数据库项目绑定。恢复时逐条验证有效性。公开数据请在数据库控制台备份。
- 站主管理：进入 Supabase → Table Editor → resources，可以删除违规记录。没有把管理员密钥放入网页，也没有不安全的隐藏管理员入口。
- 数据通过 Realtime 更新；连接中断时回退为每 15 秒自动刷新，回到标签页时也会刷新。离线提交会报错，不会假装已共享。
- 并发编辑带版本检查，避免无提示地覆盖其他设备上的修改。
- 体验区数据不会自动公开上传；正式使用后重新提交需要共享的资源。

## 使用范围与限制

这是适合小范围共享的初版。所有资源可公开读取，任何访客可新增资源。未加入验证码、审核或可靠的防刷限制，因此不要当作已经具备防滥用能力的大型公共平台。需要公开推广时，应增加服务端验证码或提交审核。

免费服务的额度、休眠和可用性以服务商当时说明为准。网站不检测网盘链接是否失效。列表分批拉取；单次最多加载 20,000 条，超出会提示升级分页查询，不会悄悄截断。

## 文件说明

- index.html：主页面及配置向导
- style.css：手机和电脑布局
- app.js：交互、权限调用、实时同步
- config.js：公开数据库连接配置（可提交仓库）
- database.sql：建表、数据库权限与编辑函数
- supabase.js：随包附带的 Supabase JS 2.49.8，无需另行安装
- SUPABASE-LICENSE.txt：第三方 SDK 许可证
- .nojekyll：GitHub Pages 静态文件标记

无需 npm、构建工具或自己购买服务器。数据库密码、service_role、secret key 均不得放入上述文件。

## 技术参考

- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/realtime/postgres-changes
- https://supabase.com/docs/guides/getting-started/api-keys
- https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site
