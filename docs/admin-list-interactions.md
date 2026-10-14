# Admin 列表交互统一

## 规则

- 记录行右侧统一省略号图标（无可见文案），复用项目 DropdownMenu，保留“更多”的无障碍名称及悬停提示。
- 点击主要名称与“更多 → 详情”进入同一详情页、详情面板或只读弹窗。
- 列表不提供价格、文案、素材、模型选择等编辑输入。编辑通过独立弹窗或现有详情页完成。
- 删除、发布、重发等执行操作置于详情或确认弹窗；保留原权限、已发布不可编辑及已分享不可删除限制。
- 布尔开关使用 Switch；场景、方案等多选保留 Checkbox，不改变其选择语义。
- 不添加轮询，不改 Backend 业务规则或 App 合同。

## 修改范围

- 共用组件：`admin/src/components/list-actions.tsx`（更多、名称、只读详情）。
- 用户及详情：UsersPage、UserDetailPage、UserContactPreferences。
- 伴侣及 AI 管理：CompanionsPage、CompanionDetailPage、AgentPage、LifeEnginePage、WorldEngineConfigDialog。
- 模型：ModelServicesPage、ModelUsagePage、MediaModelsPage。路由编辑保存仍使用现有部分更新接口。
- 商品与记录：CreditProductsPage、BillingProductsPage、BillingActivityPage。
- 内容与预设：AIPetsPage、StoryHubPage、LegalDocumentsPage、WhatsNewPage、OnboardingPage。
- 只读指标：ProductHealthPage。
- 开关配置：StoragePage。
- 文案：中英文 `listActions.more/details/close`。

## 验证状态

仅人工阅读源码核对组件契约、保存字段、原权限、加载与空数据处理，以及弹窗草稿隔离。遵守用户限制，未执行测试、类型检查、构建、Git 操作；未声称浏览器验证。

最快人工验证：先点击名称与“更多 → 详情”确认目标一致；在编辑弹窗修改后取消应不改变列表，保存后刷新应保留；删除和发布从详情发起；开关请求失败应保持服务端旧状态。分别查看中文与英文，以及用户/伴侣详情内部列表。

上线仅涉及 Admin 前端，沿用现有 Backend 接口，兼容 Backend/Admin/Webapp 先上线、App 后上线的顺序。
