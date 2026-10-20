# 金币与订阅购买修复

## 行为

- 购买前等待 RevenueCat 初始化，并确认当前 SDK App User ID 与 Vita 用户 ID
  一致。账号同步失败时不拉起支付；购买和恢复购买共用该校验。
- 通过 SDK 错误码区分失败和取消。`userCancelled: false` 不会再被字符串
  `cancel` 判断误判成取消。两种结果都有可见反馈。
- SDK 支付成功后保存交易 ID、商品 ID、购买时间和所属用户，显示同步状态。
  Backend 确认该订单已完成发放，并成功刷新余额、订阅后才提示购买成功。
- 未完成订单每 15 秒重新检查，控制器重启后从本地恢复。相同用户、相同商品
  有待确认订单时，不会再次发起购买。切换账号不会确认或显示其他用户的订单。
- 恢复购买使用同一确认流程；没有可恢复购买时不再提示恢复成功。
- `TEST_STORE` 使用 Admin 的 App 商品目录及赠币配置。
- webhook 先保存到 `revenuecat_webhook_events`，再执行发放。余额、账本、
  邀请奖励、订阅、购买记录与事件完成状态在同一事务内提交，失败完整回滚。
  后台每 10 秒扫描待处理事件，按失败次数退避，最多间隔 30 分钟，持续重试。
- 发币键在事务内通过唯一主键声明。重复事件、并发事件和已发放订单重放都
  不会重复发币；不同账号也不能复用同一购买交易发币。
- 读取完整 `entitlement_ids`，保留旧单值字段。订阅响应新增 Backend 计算的
  `is_subscribed`。过期记录不会遮挡仍有效的其他订阅，旧事件不会覆盖新状态。
- 订阅的产品变化、取消后恢复通知不再重复发放当期赠币。试用期不赠币，
  正常购买和续订按目录配置发放；年包后续月度赠币沿用现有调度。

## 上线与外部配置

1. 先执行 `backend/migrations/20261012_billing_fulfillment.sql`，再上线 Backend
   （按项目流程与 Admin 同批发布），随后上线 App。Admin 同步支持筛选 App 来源的测试商店订单。
2. RevenueCat Webhook URL 必须是能够到达实际 Backend 的 HTTPS 地址：
   `https://<Backend 域名>/v1/webhooks/revenuecat`。本地模拟器使用
   `127.0.0.1:8260` 时，RevenueCat 无法直接访问该地址，需要指向对应 Backend
   的 HTTPS 入口。测试购买应包含 SANDBOX 事件。
3. Backend 配置 `VITA_REVENUECAT_WEBHOOK_SECRET`；RevenueCat Authorization
   Header 填相同值或 `Bearer <该值>`，两种写法均验证共享秘密。未配置秘密仍
   返回 503，错误秘密仍返回 401。
4. RevenueCat 的商品 ID 应与 Admin 的 App 商品 ID 一致；Vita 用户 ID 应与
   RevenueCat Customer 当前 App User ID 对应。订阅商品需配置其权益。

**历史订单不会凭“paid”状态直接补发。** 旧代码在发放失败时也记录 paid，
新迁移只为具有真实账本发放证据的历史订单回填 `fulfilled_at`。对之前漏发的
订单，在 RevenueCat 事件详情中重新发送该笔经过验证的 webhook：新代码会
补发未完成权益，已有账本发放记录则会去重。未知商品、未知用户等事件保留
在待处理队列，修正目录或身份条件后继续处理，不丢弃事件。

## 最快验证

1. 在金币购买和订阅购买中分别选择测试失败、取消，确认都有正确提示，且
   不新增余额和权益。
2. 测试成功购买，确认界面先等待发放；到账后金币余额或订阅状态更新，再
   显示成功。暂时中断 webhook，确认只显示同步中且不会再次购买同商品。
3. 恢复 webhook 后等待检查或点击状态卡的刷新按钮，确认到账；同步中重启
   App 后也应继续检查。
4. 同一 RevenueCat 事件重放两次，确认账本与赠币只有一份。

可查账：

```sql
SELECT id,status,attempts,retry_at,last_error
FROM revenuecat_webhook_events ORDER BY created_at DESC LIMIT 20;

SELECT user_id,product_id,store_transaction_id,status,credits,fulfilled_at
FROM billing_purchases WHERE provider='revenuecat'
ORDER BY purchased_at DESC LIMIT 20;
```

自动化验证包括 App 模拟 SDK/Backend 的购买、恢复、失败、取消、延迟到账、
账号隔离及八语言文案测试，以及真实 PostgreSQL 的事务回滚、并发去重、
订阅权益数组、旧订单重放和目录修正重试。测试没有发起真实商店购买。
PostgreSQL 集成测试仅接受数据库名称以 `vita_billing_test_` 开头的
`VITA_BILLING_TEST_DSN`，并重建该专用测试数据库的 public schema，禁止
指向实际应用数据库。

## 修改文件

- Backend：`internal/handler/billing.go`、`revenuecat_fulfillment.go`、
  `revenuecat_fulfillment_test.go`、`billing_webhook_test.go`、
  `admin_billing_test.go`，`cmd/server/main.go` 及上述迁移。
- App：`lib/features/billing/billing_controller.dart`、`billing_sync_banner.dart`、
  `credits_page.dart`、`subscription_page.dart`，
  `lib/core/i18n/translations.dart`、`additional_translations.dart`，
  `test/billing_purchase_flow_test.dart`。
- 文档：本文件。

Admin 同步修改：`admin/src/api/types.ts`、`admin/src/pages/BillingActivityPage.tsx`，对齐 App 来源的购买和流水类型及筛选。
