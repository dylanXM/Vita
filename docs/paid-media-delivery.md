# 付费媒体交付

穿搭、此刻照片、听最新回复使用“预扣金币 → 生成并保存媒体 → 事务交付”。

- 穿搭和照片走 `image_requested_photo` 路由；语音走 `audio_speech`。
- 图片下载成功、内容为图片并保存到项目媒体存储后，才进入交付。
- 语音拒绝空结果和文本错误响应，先保存音频，再更新聊天消息。
- 媒体消息、穿搭所有权、装备状态与消费完成记录一起提交；交付失败回滚并退款。
- 重复请求不重复扣费；同一语音不能重复交付。已有穿搭复用照片，旧穿搭缺照片时免费补生成。
- 请求中断、供应商失败或数据库交付失败时使用独立退款上下文。服务异常退出留下的预扣由现有每分钟恢复任务处理：超过 10 分钟的保留记录退款；已退款记录不能再交付。
- 退款未能确认时返回 `refund_unconfirmed`，不会宣称退款成功，保留记录继续由恢复任务处理。
- App 在刷新余额前接收媒体，更新同 ID 的语音消息；购买失败后重新获取余额。

无新增迁移、无 API 删除。Backend + Admin 先上线（Admin 无代码改动），App 后上线；旧 App 可使用原购买接口收到媒体。

最快验证：为图片和语音路由配置可用模型，购买穿搭/照片/语音，查看真实图片、音频及金币流水；令供应商失败，再购买一次，确认显示失败且金币退回。同一成功请求使用相同幂等键重试，确认无重复消费。真实供应商、设备尚未实测。

修改文件：
- Backend：`internal/handler/experiences.go`、`experience_media.go`、`experience_media_test.go`；`internal/agent/service.go`、`client.go`、`client_test.go`、`paid_media.go`、`paid_media_test.go`；`internal/credits/service.go`。
- App：`lib/features/chat/chat_controller.dart`、`experience_sheet.dart`、`test/chat_controller_send_race_test.dart`。
- 文档：本文件。

验证覆盖专用 PostgreSQL 的预扣、交付成功、空结果退款、数据库交付回滚、退款幂等、语音重复交付、并发请求及超时恢复；模拟媒体服务覆盖有效图片、下载失败、空内容和错误内容。
