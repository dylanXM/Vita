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

生产 Compose 当前默认 `VITA_AUTO_MIGRATE=false`，因此必须完成以下操作之一：

1. 在正式流量切换前，用同版本 backend 在单实例维护窗口临时设置 `VITA_AUTO_MIGRATE=true` 启动一次；迁移成功后恢复为 `false`。
2. 将 backend 中的增量 DDL 转换为正式数据库迁移脚本，由数据库发布流程执行。

检查项：

- [ ] 迁移前完成生产数据库备份。
- [ ] beta 数据库先执行并验证迁移。
- [ ] 确认 `device_push_tokens` 和 `notification_outbox` 已创建。
- [ ] 确认迁移完成后 backend 健康检查正常。
- [ ] 确认生产环境已恢复 `VITA_AUTO_MIGRATE=false`。

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

## 官方参考

- [Firebase：Flutter 接收消息](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages)
- [Firebase：Flutter Cloud Messaging 初始化](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)
- [Firebase：FCM HTTP v1 发送与认证](https://firebase.google.com/docs/cloud-messaging/send/v1-api)
