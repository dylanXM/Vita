# Flutter App guide

## Visual standard

The App uses a WeChat-inspired mobile interface, adapted to Vita's companion
product. Preserve the existing floating iOS Liquid Glass bottom navigation; it
is an explicit product exception and must not be replaced with a WeChat tab bar
unless the user specifically requests it.

For every other surface:

- Use `context.vita` colors. Primary green is `#07C160`, outgoing chat bubbles
  use `#95EC69`, pages use a light-gray canvas, and grouped content uses flat
  white surfaces with 0.5 px separators.
- Keep navigation titles centered at 17 px. Avoid decorative gradients,
  elevated cards, large shadows and oversized rounded containers in ordinary
  list, settings and chat flows.
- Conversation lists show avatar, name, latest-message preview and latest time.
  Do not add a trailing chevron. Refresh the list after returning from chat.
- Chat messages show the companion avatar on the left and the user's avatar on
  the right. Outgoing bubbles are green; incoming bubbles are white. Preserve
  text and emoji exactly as received.
- Chat title bars show the character name as the primary title. Put secondary
  actions in the overflow/detail sheet instead of crowding the title bar.
- Prefer flat grouped rows and restrained 4-8 px radii. Material widgets may be
  used as implementation primitives, but their default Material appearance
  must not become the product's visible design language.
- Touch targets must remain at least 44 logical pixels and layouts must support
  system text scaling, safe areas, light mode and dark mode.

## Validation

- Backend/Admin/Webapp/App use the current API contract in this pre-release project.
- Update all eight App locales together: Arabic, English, Spanish, Japanese,
  Korean, Portuguese, Simplified Chinese and Traditional Chinese.
- Run `flutter test` and `flutter analyze` after changes. Add focused unit or
  widget tests for parsing, navigation and media-message behavior.
