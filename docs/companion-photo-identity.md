# 伴侣照片人物一致性

穿搭、用户请求的照片、自动生活照片必须使用当前伴侣头像作为参考图，不再只依赖外貌文字。

头像来源与 App 的 `portrait_url` 一致：优先 `companions.avatar_url`，其次头像目录的 `image_url`。支持四个 App 内置头像（Backend 内嵌同一原图）、用户媒体、Admin 上传图片、HTTP 图片及 data URL。头像缺失或加载失败时拒绝生成，付费请求沿用预扣失败退款。

适配器：
- OpenAI 兼容服务使用 multipart `/images/edits`，真实头像作为 image 文件；GPT Image 1 / 1.5 设置高输入保真。依据：[官方图片编辑接口](https://developers.openai.com/api/reference/resources/images/methods/edit)。
- KIE Sunburst 文生图 ID 在有参考图时使用其对应的 `gpt-image-2-5-sunburst-image-to-image` 调用，传入 `input_urls`。依据：[KIE 图生图文档](https://docs.kie.ai/market/gpt/gpt-image-2-5-sunburst-image-to-image)。
- KIE `google/nano-banana-edit` 使用 `image_urls`。依据：[KIE Nano Banana Edit](https://docs.kie.ai/market/google/nano-banana-edit)。
- KIE 先通过其官方文件上传接口上传头像，再传入供应商可读取的 URL，避免向供应商传 App 资源路径或需要 Vita 登录的 URL。依据：[KIE Base64 上传](https://docs.kie.ai/file-upload-api/upload-file-base-64)。
- 其他 KIE 模型尚无已验证参考图适配器，明确失败并走退款；不会回退为无参考图的文生图。

提示词明确要求保留人物面部、年龄、肤色、眼型和头发，仅改变衣服、姿势和环境。此改动补齐参考图链路，不构成人脸一致性的自动识别或质量评分；最终生成效果仍需真实模型验收。

穿搭消息保存头像来源。已有穿搭若没有对应当前头像的参考记录，重新装备时免费生成照片。历史聊天图片保留，不自动重写。

上线：仅 Backend 修改，无新增迁移或客户端 API 变更，按 Backend + Admin 同批上线（Admin 无改动），App 无需同步发版。最快验证是在相同伴侣中购买两种穿搭和一张生活照片，检查人物与头像，并检查 Admin 调用入参中的 Reference.Source；不支持的模型应失败退款。真实供应商尚未实测。

修改文件：`backend/internal/agent/client.go`、`service.go`、`paid_media.go`、`image_reference.go`、`image_reference_test.go`、`portraits/{mia,nora,leo,kai}.png`、`backend/internal/handler/experience_media.go`、本文。

验证：模拟服务检查 OpenAI multipart 头像字节、KIE 上传与对应参考字段、Sunburst 图生图选择、未知模型拒绝、默认头像读取及调用记录不保存头像字节；默认头像文件与 App 原图逐字节比对一致。
