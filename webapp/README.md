# Vita Web

Next.js Web 客户端。界面使用黑白灰；人物、头像、宠物、媒体内容保留原色。

## 本地启动

```sh
cd webapp
pnpm install --frozen-lockfile
pnpm dev
```

打开 http://127.0.0.1:5176。本地开发默认将 `/v1/*` 转发到 `http://127.0.0.1:8260`，请先启动后端；修改配置后需重启 Web 开发服务。使用其他后端时可设置 `NEXT_PUBLIC_VITA_API_URL`。生产环境不启用本地转发，API 地址需要在构建前配置；生产环境使用 HTTPS，后端允许来源需包含 Web 域名。

## 页面与接口

- 世界：伙伴当前场景、每日探访、反馈、预约入口。
- 对话：历史消息、发送文字与语音文件、异步回复轮询及失败重试、媒体展示、伙伴资料、共同体验。
- 旅程：按伙伴筛选与搜索、分页、回忆详情、编辑与删除；只读纪念保持只读。
- 探索：故事与 AI 宠物入口、后台提供的探索内容。不包含萍水相逢。
- 故事：后台故事目录、故事创建、章节阅读、分支选择。
- 宠物：领养、状态、喂食、摸摸、喝水、散步与休息。
- 我的：资料、密码、邀请、反馈、世界与联系偏好、伙伴恢复、会员及金币记录。
- 支付：PayPal 跳转审批、后端确认、等待 webhook 履约、取消自动续费。配置见 Backend 的 PAYPAL.md。

价格、权益、余额、可领养状态、计费、体验预约时间与可操作状态均以 Backend 返回为准。

## 快速验证

```sh
pnpm test
```

1. 访问首页，切换中文/英文、明暗主题，查看人物与宠物原色。
2. 在手机宽度检查折叠导航、文本可读性与表单。
3. 连接测试 Backend，用测试账号登录，查看世界、聊天、旅程、故事与宠物。
4. 用 Sandbox 买家完成金币购买和订阅，确认 webhook 发放，重复确认不能重复发放。
5. 在「我的」取消自动续费，确认当前付费周期保留。

自动化测试覆盖翻译键、入口挂载、列表兼容与媒体 URL 规则；这些测试不等同于真实账号、模型、支付或设备验证。

## Google 登录

登录与注册弹窗使用 Google Identity Services 官方按钮，将 ID token 交给现有 `/v1/auth/google` 验证；只有 Backend 返回的 Vita token 会写入会话。新 Google 账号会先进入协议确认，再注册；已有账号不需要重复注册。

Backend 的 `/v1/app-content?platform=app` 通过新增 `auth.google_client_id` 返回 `VITA_GOOGLE_CLIENT_ID`（公开 OAuth Client ID，不是 secret）。优先沿用这份配置；本地启动或本机构建、需要兼容旧 Backend 时，也可设置 `NEXT_PUBLIC_VITA_GOOGLE_CLIENT_ID`，其值必须与后端接受的 Web OAuth Client ID 一致。

在 Google Cloud OAuth 的「已获授权的 JavaScript 来源」中添加实际 Web origin；本地 `http://localhost:5176` 与 `http://127.0.0.1:5176` 需要分别配置。生产使用 HTTPS，浏览器需能访问 `https://accounts.google.com/gsi/client`。

本次 Backend 只新增公开配置字段，没有数据库迁移；按 Backend + Admin 先上线、Web 随后上线、App 后续上线即可。回滚 Web 不影响现有邮箱登录；旧 App 会忽略新增字段。

验证时分别使用已有 Google 账号、新账号（取消/同意协议）、关闭账号选择窗口、脚本加载失败后重试，并确认退出后重新登录正常。真实 Google 登录仍需配置 OAuth 来源并完成浏览器授权验证。

Google Identity Services 参考：https://developers.google.com/identity/gsi/web/guides/display-button
