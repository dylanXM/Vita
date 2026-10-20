# Flutter App guide

## Visual standard

Vita is a companion product, not a WeChat-style messenger. Keep the floating
bottom navigation and use `context.vita` theme colors throughout. World,
Journey, Discover and Me may have distinct compositions, but typography,
spacing, action hierarchy and motion should feel like one product.

- Keep each user-visible card or list item's outer size fixed. State changes,
  missing content, long text and translations must not resize its portrait or
  make neighboring items jump. Truncate within the fixed area and provide a
  suitable detail view for full content.
- Do not add sequence numbers to user-visible cards or lists.
- Give a primary action a clear visual priority. Secondary actions stay
  available without competing with it. Completing an interaction must reveal a
  meaningful next step instead of leaving prominent disabled controls.
- An important companion interaction should have visible scene/person feedback
  and an interactive continuation. A short message or generic receipt sheet
  alone is insufficient.
- Preserve message content and emoji exactly as received. Avoid copying a
  familiar messenger's bubble, header or information-page layout.
- Secondary and deeper pages slide in from the right; tab switches do not.
- Touch targets must remain at least 44 logical pixels. Support system text
  scaling, safe areas, light and dark themes, and reduced-motion settings.

## Validation

- Backend/Admin/Webapp/App use the current API contract in this pre-release project.
- Update all eight App locales together: Arabic, English, Spanish, Japanese,
  Korean, Portuguese, Simplified Chinese and Traditional Chinese.
- Run `flutter test` and `flutter analyze` after changes. Add focused unit or
  widget tests for parsing, navigation and media-message behavior.

## 用户可见列表

- 用户看到的卡片列表、信息列表，其同一列表中的每一项必须使用固定尺寸，不得根据单项内容长度或字段是否为空改变卡片高度或宽度。
- 列表内容较长时限制行数并以省略号截断；可通过详情页查看完整内容。字段为空时调整内容对齐，不改变该列表项的外部尺寸。
- 实现或修改列表时，检查短文本、长文本、缺失字段和不同语言下的尺寸一致性。
