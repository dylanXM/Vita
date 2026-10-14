# 文件与验证

## 文件范围

本次 Dock／三图／默认人物扩展新增：App `encounter_dock.dart`、`encounter_portrait.dart`；Backend `20261014_encounters_gallery.sql`、`20261014_encounters_presets.sql`、`internal/encounterart/assets.go`、`images/` 四张 PNG、`internal/handler/encounter_art.go`。同步修改角色接口、Admin 编辑弹窗、App 创建和卡片展示、多语言及人物参考图片读取。

- Backend：`migrations/20261014_encounters.sql`，`cmd/server/main.go`，`internal/handler/encounters.go`、`encounter_catalog.go`、`encounter_video_media.go`，`internal/agent/encounters.go`、`client.go`。
- Admin：`src/pages/EncounterCharactersPage.tsx`、`src/App.tsx`、`src/layout/nav.ts`、`src/i18n/locales/en.ts`、`zh-Hans.ts`。
- App：`lib/features/encounters/encounters_page.dart`、`encounter_media.dart`、`lib/features/explore/explore_page.dart`、`lib/core/i18n/encounter_translations.dart`、`translations.dart`、`pubspec.yaml`。
- 文档：本目录 `spec.md`、`plan.md`、`tasks.md`、`handoff.md`。

## 已进行的检查

仅阅读和人工复核源码：路由与鉴权、字段及 SQL 引用类型、请求参数绑定、同一会话互斥、重复请求复用、金额变化、独立上下文退款、事务交付、角色禁用和历史保留、多语言键及页面尺寸、计时器与播放器释放。核对现有金币规则并由用户确认继续要求订阅。

未执行 Git、测试、静态检查、构建、依赖解析、迁移、外部供应商调用或设备验证。源码复核不能证明这些步骤通过。

## 最快验证路径

1. 按已有发布流程执行新迁移并更新 Backend、Admin、Webapp；App 随后更新，没有新增 Webapp 界面。
2. Admin → 萍水相逢，新建公开角色，上传封面，启用；确认名称开详情、图标 More、弹窗编辑和状态 Switch。
3. App 获取新增依赖后重新启动，探索 → 萍水相逢 → 选择喜好 → 滑卡 → Chat；加号上传封面并创建私有角色，其他用户不能访问它。

Dock 扩展验证：先执行 gallery、presets 新迁移并更新 Backend、Admin，再更新 App。四个默认人物应出现在角色配置中；给任一角色配置三图，验证上方切图、下方切角色、第一张封面，以及第四张被拒绝。检查玻璃 Dock、加号点击与减少动态效果模式、后台恢复及长文本布局。图片已逐张查看；未运行上述设备、迁移、测试或构建验证。
4. 订阅用户送礼／请求照片：选商品、填写媒体需求、确认金币，验证生成期间预扣、完成后消息交付。未订阅用户进入订阅流程，余额不足进入充值流程；返回后重新确认。
5. 模型管理配置 KIE 服务与 `kling/v2-1-master-image-to-video` 模型；模块视频配置选择模型、设置实际金币价格、5 或 10 秒时长并开启。请求视频并确认结果可播放。
6. 连续重复提交原请求应只生成、扣费一次；断网后回访恢复处理中状态，供应商失败退币，禁用角色后保留历史。进程中断后的预扣由既有陈旧预扣恢复退款，原请求不会自动重新生成。

视频初版仅实现以上 KIE 协议适配器；其他供应商需要新增适配器。模型可配置不等于任意模型协议都已经支持。视频初始关闭，必须填好配置后启用。App 的新增插件和供应商真实交付仍须运行验证。
