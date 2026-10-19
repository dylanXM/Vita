# Web PayPal Sandbox

Web 新支付使用 PayPal。原有 App RevenueCat 和旧接口保持兼容。

## 上线顺序

1. 在测试数据库应用 `20261019_paypal.sql`（正常 Backend 启动迁移会执行）。
2. 配置后端变量、PayPal Sandbox plans 与 webhook，再上线 Backend + Admin。
3. Web 构建时设置 `NEXT_PUBLIC_VITA_API_URL`，再上线 Web。App 可后续独立上线。

迁移只新增表，没有删除或重命名现有字段。现有 Admin 的 Web 商品目录继续作为名称、价格、金币和权益来源；无需改动 App 商品。Sandbox 使用测试数据库和测试账号。

## 后端环境变量

```dotenv
VITA_PAYPAL_MODE=sandbox
VITA_PAYPAL_CLIENT_ID=<Sandbox REST App client ID>
VITA_PAYPAL_SECRET=<Sandbox REST App secret>
VITA_PAYPAL_WEBHOOK_ID=<同一个 Sandbox REST App 的 webhook ID>
VITA_PAYPAL_WEB_URL=http://localhost:5176
VITA_PAYPAL_PLAN_IDS={"plus_monthly":"P-REPLACE","plus_yearly":"P-REPLACE"}
```

密钥只配置在 Backend。不要添加 `NEXT_PUBLIC_` 前缀，不要把密钥提交到仓库。

`VITA_PAYPAL_PLAN_IDS` 将 Admin 中启用的 **Web 订阅 key** 映射到 Sandbox PayPal plan ID；`product_id` 仍使用现有 Vita 商品标识，供模型/宠物权限等关联规则使用，不能替换成 PayPal plan ID。金币无需 PayPal plan，使用 Orders v2 单次购买。

每个 PayPal plan 必须：ACTIVE、USD、单一 REGULAR 无限续费周期、interval_count=1、MONTH 或 YEAR 与目录相符、无试用和非零 setup fee、价格与目录一致。服务端在创建订阅前逐项核对。

未配置凭证或 webhook 时，目录返回 `available=false`，前端不能发起购买。

## Webhook

在对应 Sandbox REST App 注册公网 HTTPS 地址：

```text
https://<backend-host>/v1/webhooks/paypal
```

订阅事件：

- CHECKOUT.ORDER.APPROVED
- PAYMENT.CAPTURE.COMPLETED
- PAYMENT.SALE.COMPLETED
- BILLING.SUBSCRIPTION.ACTIVATED / UPDATED / CANCELLED / SUSPENDED / EXPIRED
- PAYMENT.CAPTURE.REFUNDED / REVERSED
- PAYMENT.SALE.REFUNDED / REVERSED

通知先通过 PayPal 的验签接口验证；金币订单重新读取并捕获 PayPal order，再校验交易、币种与快照金额。订阅激活通知本身不发放权益，完成付款通知才发放。非 2xx 通知必须由 PayPal 重试，避免未提交的数据被误认为履约成功。

履约在同一数据库事务中记录交易、发放金币、写入购买记录；唯一交易 ID 和发放键防止重复。年付会员首期发放月度金币，后续每小时检查到期月度额度。取消续费保留已经付费的周期。

## API

- GET `/v1/paypal/catalog`
- POST `/v1/paypal/checkouts`：`kind`（coin/subscription）、`product_key`、`idempotency_key`
- POST `/v1/paypal/checkouts/:id/confirm`：仅能查询本人 checkout，返回 confirmed/pending
- POST `/v1/paypal/subscriptions/:id/cancel`：Vita subscription ID，后端核验所有权
- POST `/v1/webhooks/paypal`：PayPal 签名通知

浏览器不得使用返回 URL 中的付款状态发放金币或会员。

## 验证

```sh
go test ./internal/paypal ./internal/handler -run 'Test(PayPal|RequestUsesServerCredentialsAndIdempotency|RequestRejectsProviderErrors|ApprovalURLRestrictsDestinations)' -count=1
```

还必须在测试 PostgreSQL 和真实 Sandbox 上验证：单次购买、重复确认/通知、订阅首次付款及续费、支付后关闭页面、取消/到期、退款及支付期间修改目录价格。单元测试不代表已经通过以上集成验证。

PayPal 官方文档：
- https://developer.paypal.com/docs/api/orders/v2/
- https://developer.paypal.com/docs/api/subscriptions/v1/
- https://developer.paypal.com/docs/api/webhooks/v1/
