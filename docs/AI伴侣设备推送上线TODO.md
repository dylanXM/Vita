# AI 伴侣后台生活与设备推送上线 TODO

适用范围：AI 伴侣后台生活事件、主动触达、iOS/Android 系统通知。

上线顺序：backend + admin + webapp 同批上线，App 后续发布。

## 1. 上线阻塞项

- [ ] 将当前占位应用标识 `com.example.vita` 替换为正式 Android Application ID 和 iOS Bundle ID。
- [ ] 创建 Firebase 项目，并分别添加正式 Android、iOS App。
- [ ] 如 beta 与 prod 需要数据和推送隔离，为两个环境配置不同的 Firebase App 参数和后端服务账号。
- [ ] 启用 Firebase Cloud Messaging API（HTTP v1）。
- [ ] 创建只用于服务端推送的 Google Service Account，并授予 Firebase Cloud Messaging API Admin 权限。
- [ ] 为 iOS 创建 APNs Authentication Key，并上传到 Firebase Cloud Messaging 配置。
- [ ] 准备真实 Android 和 iOS 设备。iOS 推送不能只依赖 Simulator 完成上线验收。
- [ ] 为生产配置稳定的 `VITA_AGENT_CONFIG_KEY`，不得继续使用示例占位值。
- [ ] 在生产发布前执行新增数据库结构迁移。

## 2. App Firebase 配置

分别填写：

- `app/config/beta.json`
- `app/config/prod.json`

需要配置以下字段：

```json
{
  "VITA_FIREBASE_PROJECT_ID": "Firebase project ID",
  "VITA_FIREBASE_API_KEY": "Firebase App API key",
  "VITA_FIREBASE_MESSAGING_SENDER_ID": "Firebase sender ID / project number",
  "VITA_FIREBASE_ANDROID_APP_ID": "Android Firebase App ID",
  "VITA_FIREBASE_IOS_APP_ID": "iOS Firebase App ID",
  "VITA_FIREBASE_IOS_BUNDLE_ID": "正式 iOS Bundle ID"
}
```

检查项：

- [ ] Android Firebase App 的包名与 `applicationId` 完全一致。
- [ ] iOS Firebase App 的 Bundle ID 与 Xcode Runner Target 完全一致。
- [ ] beta 构建使用 `config/beta.json`。
- [ ] prod 构建使用 `config/prod.json`。
- [ ] App 首次登录后出现系统通知授权弹窗。
- [ ] 设置页“设备通知”能够打开系统通知设置。

## 3. iOS APNs 配置

- [ ] Apple Developer 中为正式 App ID 开启 Push Notifications capability。
- [ ] 创建 APNs Authentication Key（`.p8`）。
- [ ] 记录 Key ID 和 Apple Team ID。
- [ ] 在 Firebase Console 的 iOS App Cloud Messaging 页面上传 `.p8`、Key ID 和 Team ID。
- [ ] 使用包含 `aps-environment` 权限的 provisioning profile 签名。
- [ ] Debug/beta 使用 development APNs 环境，正式 Release 使用 production 环境。
- [ ] 在真实 iPhone 上确认系统设置中 Vita 的“允许通知”已开启。

项目已经包含：

- `app/ios/Runner/Runner.entitlements`
- `UIBackgroundModes = remote-notification`
- Push Notifications entitlement

## 4. Android 配置

- [ ] Firebase Android App 使用正式 Application ID。
- [ ] 确认目标设备包含 Google Play Services。
- [ ] Android 13 及以上系统允许 Vita 发送通知。
- [ ] 确认 `POST_NOTIFICATIONS` 权限保留在 AndroidManifest。
- [ ] 使用 beta 配置构建并安装一次真实 APK。

项目使用代码注入的 `FirebaseOptions`，不要求提交 `google-services.json`。Firebase 公共 App 参数通过 `--dart-define-from-file` 注入。

## 5. 后端 FCM 凭据

后端需要以下环境变量：

```dotenv
VITA_FIREBASE_PROJECT_ID=your-firebase-project-id
VITA_FIREBASE_SERVICE_ACCOUNT_BASE64=base64-encoded-service-account-json
```

生成 Base64：

```bash
base64 < firebase-service-account.json | tr -d '\n'
```

配置位置：

- `deploy/.env.beta`
- `deploy/.env.prod`

安全要求：

- [ ] 服务账号 JSON 和 Base64 内容不得提交到 Git。
- [ ] beta 与 prod 凭据存放在部署平台的 Secret 管理系统或受限环境文件中。
- [ ] 服务账号不得授予项目 Owner/Editor 等超范围权限。
- [ ] 制定服务账号私钥轮换流程；轮换时先更新环境变量，再废弃旧私钥。
- [ ] 后端日志不得输出 Service Account JSON、私钥、OAuth Token 或设备 Token。

兼容环境变量 `VITA_FCM_CREDENTIALS_JSON` 仍可读取原始 JSON，但正式环境统一使用 Base64 变量。

## 6. 数据库迁移

本次依赖以下新增或扩展结构：

- `notification_outbox`
- `device_push_tokens`
- AI Provider、Model、Agent Settings、Life Events、Companion Days 等 Agent 表和字段

Backend 镜像已经包含独立的 `/app/migrate` 程序，beta/prod Compose 也包含一次性 `migrate` 服务。正式环境保持 `VITA_AUTO_MIGRATE=false`，禁止通过临时开启 API 自动迁移来发布。

执行顺序：

1. 停止写入或进入维护窗口。
2. 完成数据库快照/备份，并记录备份 ID。
3. 构建与待发布 API 完全相同版本的镜像。
4. 单独执行迁移并确认退出码为 0：

```bash
cd deploy
docker compose -p vita-prod -f docker-compose.prod.yml --env-file .env.prod build migrate api
docker compose -p vita-prod -f docker-compose.prod.yml --env-file .env.prod run --rm migrate
```

5. 检查关键表和字段后再启动 API、Admin、Webapp：

```bash
docker compose -p vita-prod -f docker-compose.prod.yml --env-file .env.prod up -d api admin webapp
```

检查项：

- [ ] 迁移前完成生产数据库备份。
- [ ] beta 数据库先执行并验证迁移。
- [ ] 确认 `device_push_tokens` 和 `notification_outbox` 已创建。
- [ ] 确认迁移完成后 backend 健康检查正常。
- [ ] 确认生产环境已恢复 `VITA_AUTO_MIGRATE=false`。

## 6.1 首次创建 PostgreSQL

1. 在云数据库控制台创建 PostgreSQL 实例，版本使用供应商仍在安全支持期内的稳定版本。
2. 创建独立数据库 `vita` 和最小权限运行账号；不要使用数据库超级管理员账号运行 API。
3. 只允许 Backend 所在私网或固定出口 IP 访问 5432，禁止直接向全公网开放。
4. 开启自动备份和时间点恢复（PITR），保留期至少覆盖一次完整发布回滚窗口。
5. 下载供应商 CA 证书，并按供应商要求使用 `sslmode=verify-full`；仅在供应商明确只支持 `require` 时使用 `sslmode=require`。
6. 拼出连接串并写入部署 Secret：

```dotenv
VITA_DB_DSN=postgres://vita_app:<password>@<private-host>:5432/vita?sslmode=verify-full
```

7. 从 Backend 部署主机执行一次连接测试，再运行上面的 `migrate` 服务。

## 6.2 首次创建 Redis

1. 在与 Backend 相同地域创建托管 Redis，并启用密码或 ACL 用户。
2. 只允许 Backend 私网访问 Redis 端口，禁止公网匿名访问。
3. 若供应商支持 TLS，使用 `rediss://`；否则必须确保连接只经过可信私网。
4. 将完整 URL 写入部署 Secret，路径最后的数字是 Redis DB：

```dotenv
VITA_REDIS_URL=rediss://:<password>@<private-host>:6379/0
```

5. Backend 启动时会解析 URL 并执行 `PING`；连接、密码或证书错误会直接阻止服务启动。

## 7. 发布顺序

### 第一阶段：backend + admin + webapp

- [ ] 执行数据库迁移。
- [ ] 配置 `VITA_AGENT_CONFIG_KEY`。
- [ ] 配置 Firebase Project ID 和服务账号 Base64。
- [ ] 发布 backend、admin、webapp。
- [ ] 在 Admin 配置 OpenAI/Claude Provider、文本模型和 chat/life/proactive 模型路由。
- [ ] 检查 Agent worker 日志没有持续报错。

此阶段旧 App 没有 Push Token，后台仍会生成生活事件和主动消息；消息保存在会话中。没有有效设备时不会发送系统通知，超过六小时的通知会过期，不会在新 App 上线后集中补发旧通知。

### 第二阶段：App

- [ ] 填写对应环境 Firebase App 参数。
- [ ] 构建 beta Android/iOS App。
- [ ] 完成双平台真实设备验收。
- [ ] 构建并发布 prod App。
- [ ] 确认用户升级后设备 Token 成功注册。

## 8. Beta 真实设备验收

至少准备一台 Android 真机和一台 iPhone 真机。

系统限制：App 必须至少成功启动并完成一次 FCM 注册。Android 用户在系统设置中“强行停止”App、或 iOS 用户从多任务界面强制结束后，应重新打开一次 App 再验证后续后台消息；这是操作系统和 FCM 的投递限制，不应通过 App 内弹窗绕过。

### Token 生命周期

- [ ] 首次登录后系统请求通知权限。
- [ ] 用户允许后，`device_push_tokens` 出现对应用户和平台记录。
- [ ] 重启 App 后不会生成重复 Token 记录。
- [ ] Token 刷新后后端记录同步更新。
- [ ] 同一账号登录两台设备，两台设备均有有效记录。
- [ ] 退出登录后当前设备 Token 被禁用。

检查 SQL：

```sql
SELECT user_id, platform, enabled, last_seen_at, updated_at
FROM device_push_tokens
ORDER BY updated_at DESC;
```

### 后台生活事件

- [ ] App 完全关闭时，`companion_days` 仍按人物当地日期生成计划。
- [ ] 每天事件数量符合 Admin 配置范围。
- [ ] 生活事件不会因 backend 重启而重复生成。
- [ ] 安静时段不会发送主动消息。
- [ ] 同一人物两次主动消息至少间隔两小时。
- [ ] 新建人物在创建后一小时内不会立即主动触达。
- [ ] 每日主动消息数不超过 Admin 配置上限。

### 系统通知

- [ ] App 在后台时收到系统通知横幅、声音和通知中心记录。
- [ ] App 被正常关闭时仍收到系统通知。
- [ ] 点击通知进入正确人物的聊天页面。
- [ ] 对应主动消息已写入聊天记录。
- [ ] 同一条主动消息不会重复推送。
- [ ] 多设备均能收到同一账号的触达通知。
- [ ] 用户关闭系统通知权限后不出现 App 内替代弹窗。
- [ ] 用户重新开启系统通知后，新触达能够恢复。
- [ ] 过期或卸载设备 Token 被自动禁用。

检查 SQL：

```sql
SELECT channel, status, attempts, last_error, created_at, sent_at
FROM notification_outbox
ORDER BY created_at DESC
LIMIT 100;
```

预期状态：

- `sent`：至少一台有效设备发送成功。
- `ready`：等待首次发送或重试。
- `processing`：某个 backend 实例已领取任务。
- `failed`：所有 Token 已失效或任务无法继续。
- `expired`：通知超过六小时，不再打扰用户。

## 9. 故障与回滚

### 只停止设备推送

- [ ] 清空 backend 的 `VITA_FIREBASE_PROJECT_ID` 和 `VITA_FIREBASE_SERVICE_ACCOUNT_BASE64` 后重启 backend。

Life Engine 和聊天消息仍继续工作，Push Outbox 保留，App 不会收到系统通知。

### 停止整个后台 Life Engine

- [ ] 设置 `VITA_AGENT_ENABLED=false` 并重启 backend。

这会停止每日生活计划和主动触达 worker，不影响用户主动发起的普通聊天回复。

### 故障排查顺序

1. 检查 `notification_outbox.status`、`attempts`、`last_error`。
2. 检查用户是否存在有效 `device_push_tokens`。
3. 检查 Firebase Cloud Messaging API 是否启用。
4. 检查 Service Account 权限和私钥是否有效。
5. iOS 检查 APNs Key、Team ID、Bundle ID 和 provisioning profile。
6. Android 检查 Application ID、Google Play Services 和系统通知权限。

## 10. 上线完成标准

- [ ] backend 在无人在线时持续生成生活事件。
- [ ] 主动触达决策不依赖 App 进程。
- [ ] Android 后台和关闭状态系统通知通过。
- [ ] iOS 后台和关闭状态系统通知通过。
- [ ] 通知点击跳转正确。
- [ ] 安静时段、日上限、两小时间隔和六小时过期规则全部通过。
- [ ] beta 连续运行至少 24 小时，无重复事件、重复推送或持续重试错误。
- [ ] 生产密钥、Firebase 配置和数据库备份均已完成。

## 11. 生产环境变量完整清单

先复制模板并限制文件权限；更推荐直接写入部署平台的 Secret 管理系统：

```bash
cp deploy/.env.prod.example deploy/.env.prod
chmod 600 deploy/.env.prod
```

### 11.1 必填基础变量

```dotenv
VITA_ENV=prod
VITA_DB_DSN=<第 6.1 节得到的 PostgreSQL DSN>
VITA_REDIS_URL=<第 6.2 节得到的 Redis URL>
VITA_JWT_SECRET=<至少 32 字符的独立随机值>
VITA_JWT_ACCESS_TTL=15m
VITA_JWT_REFRESH_TTL=720h
VITA_AGENT_CONFIG_KEY=<至少 32 字符、与 JWT 不同的独立随机值>
VITA_ALLOWED_ORIGINS=https://admin.<正式域名>,https://app.<正式域名>
VITA_ADMIN_EMAIL=<首个管理员邮箱>
VITA_ADMIN_PASSWORD=<首个管理员强密码>
VITA_SMTP_HOST=<SMTP 主机>
VITA_SMTP_PORT=587
VITA_SMTP_USERNAME=<SMTP 用户>
VITA_SMTP_PASSWORD=<SMTP 专用密码或授权码>
VITA_SMTP_FROM=<发件邮箱>
VITA_SMTP_FROM_NAME=Vita
WEBAPP_API_URL=https://api.<正式域名>
```

在本机生成两个互不相同的随机密钥：

```bash
openssl rand -base64 48
openssl rand -base64 48
```

不要把命令输出贴入聊天、工单、日志或任何受 Git 管理的文件。

### 11.2 按功能启用的变量

```dotenv
# Google 登录
VITA_GOOGLE_CLIENT_ID=<Google OAuth Web Client ID>

# RevenueCat；启用移动端购买时必填
VITA_REVENUECAT_WEBHOOK_SECRET=<RevenueCat Webhook Authorization secret>

# Stripe；启用 Web 订阅时全部必填
VITA_STRIPE_SECRET_KEY=<Stripe restricted/secret key>
VITA_STRIPE_WEBHOOK_SECRET=<Stripe endpoint signing secret>
VITA_STRIPE_PRICE_PLUS=<Plus recurring Price ID>
VITA_STRIPE_PRICE_PREMIUM=<Premium recurring Price ID>

# 系统推送
VITA_FIREBASE_PROJECT_ID=<Firebase Project ID>
VITA_FIREBASE_SERVICE_ACCOUNT_BASE64=<服务账号 JSON 的单行 Base64>
```

未启用 RevenueCat 或 Stripe 时对应 Webhook 会返回 503，不会在未配置密钥时接受任何事件。

### 11.3 SMTP 获取步骤

1. 选择支持生产事务邮件的服务商，完成发件域名验证。
2. 在服务商控制台添加 SPF 和 DKIM DNS 记录，等待状态变为验证成功。
3. 添加 DMARC 记录；初期可使用监控策略，确认无误后再提高拒绝策略。
4. 创建只用于 Vita 的 SMTP 用户/授权码，不要使用邮箱网页登录密码。
5. 优先选择 587 + STARTTLS；服务商只支持隐式 TLS 时使用 465。
6. 将主机、端口、用户名、授权码和 From 地址写入 Secret。
7. 在 beta 分别验证注册邮件、60 秒重发限制、5 分钟过期和错误验证码。
8. 此前示例文件中出现过 SMTP 凭据，必须在邮件服务商控制台撤销旧授权码并创建新授权码；还需要由仓库管理员从远程 Git 历史中清除旧值。

## 12. Google 登录配置步骤

1. 打开 Google Cloud Console，新建或选择正式项目。
2. 配置 OAuth consent screen，填写应用名称、支持邮箱、隐私政策 URL、用户协议 URL和已验证域名。
3. 创建 Web OAuth Client，复制 Client ID 到 Backend 的 `VITA_GOOGLE_CLIENT_ID` 和 App 的 `VITA_GOOGLE_SERVER_CLIENT_ID`。
4. 创建 Android OAuth Client：包名必须等于最终 `VITA_ANDROID_APPLICATION_ID`；SHA-1/SHA-256 必须来自正式上传签名证书。
5. 创建 iOS OAuth Client：Bundle ID 必须等于 Xcode Runner 的正式 Bundle ID。
6. 下载 iOS `GoogleService-Info.plist`，按 Google Sign-In 文档把 `REVERSED_CLIENT_ID` 添加到 Runner Target 的 URL Types。
7. 不要将 OAuth Client Secret 放进 App；移动端只配置公开 Client ID。
8. 在 beta 真机分别验证新用户登录、已有邮箱合并、被封禁用户拒绝登录。

## 13. RevenueCat 与商店商品配置步骤

项目内置商品目录如下，适用于 iOS、Android 以及 dev、beta、prod 三个环境：

| Product ID | 类型 | 建议美元价格 | 发放金币 |
| --- | --- | ---: | ---: |
| `vita.plus.monthly` | Plus 月付 | $9.99 | 每次购买/续订 500 |
| `vita.plus.yearly` | Plus 年付 | $79.99 | 有效期内每月 500 |
| `vita.premium.monthly` | Premium 月付 | $19.99 | 每次购买/续订 1,200 |
| `vita.premium.yearly` | Premium 年付 | $159.99 | 有效期内每月 1,200 |
| `vita.coins.100` | 消耗型金币包 | $1.99 | 100 |
| `vita.coins.500` | 消耗型金币包 | $7.99 | 500 |
| `vita.coins.1200` | 消耗型金币包 | $14.99 | 1,200 |

年付首次购买时立即发放第一个月额度，Backend 此后以购买日为锚点每小时检查并补发到期月份；月底购买会在短月份按最后一天发放。每月批次具有数据库唯一键，服务重启、Webhook 重放或多实例执行不会重复发放。用户关闭自动续订后，在已付年度有效期结束前仍会按月收到额度。Apple/Google 的实际本地化价格是购买页的最终价格来源。

1. 先在 App Store Connect 和 Google Play Console 创建正式 App，包名/Bundle ID 必须与构建配置一致。
2. 在两个商店分别创建 Plus、Premium 自动续订商品和金币消耗型商品；记录每个平台的 Product ID。
3. 在 RevenueCat 创建 Project，并添加 iOS、Android App。
4. 按 RevenueCat 指引配置 App Store Connect In-App Purchase Key、Google Play Service Account；只授予购买和订阅所需权限。
5. 导入商店商品，创建 Entitlements 与 Offerings，并确保 Product ID 与 Admin 中的订阅方案、金币包完全一致。
6. 从 RevenueCat Project Settings 复制 iOS/Android Public SDK Key，分别写入 beta/prod App 配置的 `VITA_REVENUECAT_KEY`。这是公开 SDK Key，不能使用 RevenueCat Secret API Key。
7. 在 RevenueCat 创建 Webhook：
   - URL：`https://api.<正式域名>/v1/webhooks/revenuecat`
   - Authorization Header：生成一个独立随机值，并把同一个值写入 Backend `VITA_REVENUECAT_WEBHOOK_SECRET`
   - 至少订阅 purchase、renewal、cancellation、uncancellation、expiration、product change、transfer 事件
8. App 登录后会调用 RevenueCat `logIn(Vita user_id)`；退出和注销时会 `logOut`。验收时确认 RevenueCat Customer 的 App User ID 是 Vita UUID，而不是匿名 `$RCAnonymousID`。
9. 使用 StoreKit Sandbox 和 Google License Tester 验证购买、恢复、续订、退款、过期、重复 Webhook 和跨设备登录。

## 14. Android 正式签名与构建

1. 在 Google Play Console 创建正式应用并确定唯一 Application ID；创建后不能更改。
2. 创建上传密钥并放在受限目录，不要放入仓库：

```bash
keytool -genkeypair -v -keystore vita-upload.jks -keyalg RSA -keysize 4096 -validity 10000 -alias vita-upload
```

3. 构建机器设置以下环境变量：

```dotenv
VITA_ANDROID_APPLICATION_ID=<正式 Application ID>
VITA_ANDROID_KEYSTORE=<vita-upload.jks 的绝对路径>
VITA_ANDROID_KEYSTORE_PASSWORD=<keystore 密码>
VITA_ANDROID_KEY_ALIAS=vita-upload
VITA_ANDROID_KEY_PASSWORD=<key 密码>
```

4. 将最终 Application ID 注册到 Firebase Android App 和 Google OAuth Android Client。
5. 填写 `app/config/prod.json` 后构建：

```bash
cd app
flutter build appbundle --release --dart-define-from-file=config/prod.json
```

Release 构建缺少上述任一签名变量或仍使用 `com.example.vita` 时会明确失败，不会再生成 debug 签名的正式包。

## 15. iOS 签名、Bundle ID 与 Google URL Scheme

1. 在 Apple Developer 创建唯一 App ID，并开启 Push Notifications 和 In-App Purchase capability。
2. 在 Xcode 打开 `app/ios/Runner.xcworkspace`，选择 Runner Target，将 Bundle Identifier 改成正式值。
3. 在 Signing & Capabilities 选择正式 Team，启用 Automatically manage signing 或选择正式 Distribution Profile。
4. 在 Runner 的 URL Types 添加 Google iOS Client 的 `REVERSED_CLIENT_ID`。
5. 确认 `Runner.entitlements` 的推送能力被 Release 配置引用。
6. 在 App Store Connect 创建应用记录、隐私问卷、订阅说明、审核账号和支持 URL。
7. 填写 `app/config/prod.json` 后执行：

```bash
cd app
flutter build ipa --release --dart-define-from-file=config/prod.json
```

8. 将 IPA 上传 TestFlight，必须在真实 iPhone 验证登录、购买、恢复购买、推送、麦克风权限和注销账户。

## 16. 隐私政策、用户协议和账户注销

1. 在正式 HTTPS 域名发布可公开访问的隐私政策和用户协议页面。
2. 隐私政策至少说明：账号信息、聊天与 AI 内容、设备 Token、支付记录、日志、第三方模型/Firebase/RevenueCat、数据保留和删除方式。
3. 用户协议至少说明：AI 内容属性、禁止内容、虚拟商品、订阅续费、退款渠道和责任边界。
4. 将 URL 写入 App 环境文件：

```json
{
  "VITA_PRIVACY_POLICY_URL": "https://www.<正式域名>/privacy",
  "VITA_TERMS_OF_SERVICE_URL": "https://www.<正式域名>/terms"
}
```

5. App 设置页已提供隐私政策、用户协议和永久注销入口。注销会删除 Vita 服务端账号数据；Apple/Google 商店订阅仍需用户在系统订阅管理中取消。
6. 用有聊天、生活事件、积分和购买记录的 beta 账号执行注销，确认无法再登录且相关业务数据已删除。

## 17. 域名、HTTPS 与反向代理

1. 准备至少三个域名：API、Admin、Webapp，例如 `api.example.com`、`admin.example.com`、`app.example.com`。
2. 将 DNS A/AAAA/CNAME 指向负载均衡或反向代理，不要把 PostgreSQL、Redis 直接暴露到公网。
3. 在负载均衡或 Nginx/Caddy 配置受信任 CA 签发的 TLS 证书和自动续期。
4. 仅由反向代理访问 Compose 的本机绑定端口；生产 `.env.prod` 保持 `BIND_HOST=127.0.0.1`、`ADMIN_BIND_HOST=127.0.0.1`、`WEBAPP_BIND_HOST=127.0.0.1`。
5. 将 Admin/Webapp 的真实 HTTPS Origin 填入 `VITA_ALLOWED_ORIGINS`，不要填写 `*`。
6. API 代理需保留 `Host`、`X-Forwarded-For`、`X-Forwarded-Proto`，媒体上传请求体上限至少 10 MB。
7. 上线后从公网验证：

```bash
curl -fsS https://api.<正式域名>/v1/health
curl -I https://admin.<正式域名>/
curl -I https://app.<正式域名>/
```

## 18. 完整发布操作顺序

1. 在 beta 配齐本文件全部必填变量和外部账号。
2. 运行 Backend、Admin、Webapp、App 的全部测试与静态检查。
3. 渲染 Compose，确保没有 unresolved variable：

```bash
cd deploy
docker compose -p vita-beta -f docker-compose.beta.yml --env-file .env.beta config
```

4. 备份 beta 数据库，运行 `migrate`，再启动 API、Admin、Webapp。
5. 在 Admin 配置文本、图片、音频模型的默认模型和有序备选模型；未实现的视频和实时通话路由保持关闭。
6. 完成注册、登录、Token 自动刷新、聊天、生活事件、推送、媒体权限、金币扣费、购买、退款和注销全链路验收。
7. beta 连续运行至少 24 小时并检查告警、任务重试和重复事件。
8. 创建生产数据库备份，使用同一个已验收镜像运行生产迁移。
9. 发布 backend + admin + webapp，验证 `/v1/health`、Admin 登录和 Webhook 签名。
10. 最后构建并提交 Android/iOS App；等待商店审核期间不得对已发布 API 做破坏性修改。

## 官方参考

- [Firebase：Flutter 接收消息](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages)
- [Firebase：Flutter Cloud Messaging 初始化](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)
- [Firebase：FCM HTTP v1 发送与认证](https://firebase.google.com/docs/cloud-messaging/send/v1-api)
