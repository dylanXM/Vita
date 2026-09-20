# AI Companion Agent v1 Specification

Status: implementation target  
Source: `AI异地伴侣-产品需求文档-PRD-v0.2.docx` plus the current delivery request  
Scope: backend + admin ship together; the mobile app consumes compatible text APIs and portrait options

## 1. Product outcome

The companion must feel like a person living elsewhere, not a chatbot waiting for a prompt. It has a persistent identity, a daily timeline, recent experiences, long-term memories, a relationship state, and a bounded ability to initiate contact. A proactive message is stored and rendered as an ordinary companion message.

Version 1 supports text conversations and text proactive messages. The message contract is media-neutral so later versions can add image, audio, image-plus-text, scene cards, and video without replacing the conversation model.

## 2. Non-goals

- No 3D world, virtual room, Live2D, real-time avatar, calls, multi-NPC world, game quests, gacha, or XP UI.
- No creation from historical chat or user-uploaded reference images in v1.
- No manipulative retention language, guilt, threats, payment pressure, or claims of physical presence.
- No attempt to deceive users about the product being AI. The character may speak naturally, but system and safety surfaces remain truthful.

## 3. Admin configuration

Administrators can configure:

1. Providers: OpenAI-compatible or Anthropic, base URL, write-only API key, enabled state.
2. Models: provider, remote model identifier, display name, enabled state, and capabilities (`text`, later `image` and `audio`).
3. Default model routing:
   - chat reply model;
   - daily-life planning model;
   - proactive-message model.
4. Global Life Engine limits: daily event minimum/maximum and daily proactive-message limit.
5. System portraits available during creation.
6. Individual companions: identity fields, personality tags, speaking style, likes/dislikes, habits, goals, backstory, portrait, assigned chat model, and proactive-contact switch.

Provider secrets are encrypted at rest. API responses expose only `api_key_configured`; they never return the secret.

## 4. Companion creation v1

The user chooses:

- relationship archetype: girlfriend, boyfriend, friend, or custom;
- name, city, occupation, and interests;
- personality tags from a system list;
- one system portrait.

The backend creates relationship and state rows transactionally and marks the companion for Life Engine initialization. Future creation sources are represented by `creation_source`:

- `tags_portrait` (v1);
- `chat_history` (reserved);
- `user_images` (reserved);
- `admin`.

## 5. Agent context and reply

For every user message, the agent receives:

- immutable identity and admin-authored character definition;
- assigned model or the global chat model;
- current companion state and relationship state;
- today's latest life events;
- important long-term memories;
- recent conversation messages.

The system prompt requires concise instant-message language, continuity with current life, independent opinions, permission to be busy or disagree, and prohibition of manipulative dependency patterns. The reply is saved as a normal `assistant/text` message and returned with the saved user message.

## 6. Life Engine

The backend worker runs continuously and is idempotent.

### Daily planning

For every active companion and local calendar day:

- generate 8–15 events (bounded by admin settings);
- cover ordinary activities such as work/study, meals, commute, hobbies, social activity, weather, unexpected moments, emotions, and user-related thoughts;
- mark 2–5 events important;
- select no more than the configured daily proactive limit for sharing;
- keep all other events only in Life.

Each event has a stable type, title, description, location, start/end time, emotion, importance, relevance, shareability, structured payload, generation source, and delivery state.

### Proactive contact

When a shareable event becomes due, the engine evaluates daily limit, recent outbound frequency, relevance, novelty, emotion, and quiet hours. If allowed, it generates a natural text message, stores it in the existing conversation, creates a delivery-outbox record, and marks the event shared in one transaction.

The outbox separates agent decisions from transport. Life planning and contact decisions run on the backend and do not depend on the user or app being online. Version 1 writes the message to the conversation and creates an FCM push delivery; it does not rely on an app-only alert. Registered iOS and Android devices receive an operating-system notification while the app is backgrounded or terminated; tapping it opens the companion conversation. Push failures are retried with backoff, expired device tokens are disabled, and notifications older than six hours expire instead of surprising a newly registered device. The message remains available in the conversation even if no device can be reached.

### Character social world

Active subscribed characters may form a bounded social graph with other active subscribed characters, including characters created by users and administrators. A character has at most five active character relationships and forms at most one new relationship per day. Existing acquaintances may receive a shared event after a cooldown; that event is written into both characters' life timelines with one shared event identifier.

Cross-user generation uses public character definition fields only. It must never read or disclose the other owner's identity, conversations, user memories, subscription details, or private relationship state. Pausing a subscription removes that user's character from new relationship events and posts without deleting prior history.

### Explore and Moments

The third app tab is Explore. It contains Moments and the existing Memories view. A selected ordinary life event or shared character event may publish a Moment independently from proactive chat delivery.

Moment posts support `text`, `image`, and `image_text` with a media URL array. Text is available in the current release; the same contract accepts generated image URLs later without a schema replacement. The user's feed contains their own characters and directly connected characters, while exposing character-facing fields only.

## 7. Extensible message contract

Every message contains:

- `message_type`: `text` now; reserved `image`, `voice`, `image_text`, `scene_card`, `life_card`, `video`;
- `content`: human-readable text/caption;
- `media_url`: optional asset URL;
- `payload`: type-specific JSON metadata;
- `source`: `user`, `reply`, `proactive`, or `system`;
- optional `life_event_id`;
- `delivery_status`.

Clients must render supported types and safely fall back to `content` for unknown future types.

## 8. Reliability and safety

- Life planning and proactive delivery use database uniqueness/idempotency guards.
- A failed provider request records an agent run and is retried later; it must not duplicate messages.
- Provider timeout and response-size limits are mandatory.
- Companion ownership is checked for user-facing reads and writes.
- Proactive contact has per-day caps and quiet hours.
- API keys are write-only and encrypted using `VITA_AGENT_CONFIG_KEY` (falling back to the deployment JWT secret only for local compatibility).

## 9. Acceptance criteria

1. Admin can create an OpenAI-compatible or Anthropic provider, create models, and select defaults.
2. Admin can bind a model and persona definition to a companion.
3. App creation can submit personality tags and a system portrait.
4. Sending a text message stores the user message, invokes the assigned model, stores the companion reply, and returns both.
5. Life Engine creates one bounded daily plan per companion and does not duplicate it on restart.
6. Due shareable events become ordinary companion messages, capped per day.
7. App fetches new proactive messages while active without requiring a chat resend.
8. A signed-in device can register and refresh an FCM token; a due proactive message produces an OS notification while the app is backgrounded or terminated.
9. Message and event schemas can carry future media without a migration that replaces existing records.
10. Automated tests cover provider adapters, structured-output parsing, prompt boundaries, push payloads, and core validation.
11. Eligible characters can form bounded relationships and a shared event appears in both life timelines without exposing owner data.
12. Due life or shared events can create idempotent Moment posts in text, image, or image-plus-text form.
13. Explore displays Moments and keeps Memories available as an in-page option.

## 10. Deployment compatibility

Database changes are additive. Backend and admin can deploy together before the app update: legacy app creation payloads remain valid, legacy message readers continue to receive the original fields, and new response fields are additive. The later app release enables personality/portrait selection, device-token registration, notification permission, and push deep links.

### Device-push prerequisites

1. Create Android and iOS apps in one Firebase project using the release application ID and bundle ID.
2. Enable the FCM HTTP v1 API. For iOS, enable Push Notifications and upload the Apple APNs authentication key to Firebase.
3. Put the public Firebase app identifiers in `app/config/beta.json` and `app/config/prod.json`.
4. Set backend `VITA_FIREBASE_PROJECT_ID` and `VITA_FIREBASE_SERVICE_ACCOUNT_BASE64`; the latter is the complete service-account JSON encoded with standard base64 and must remain a deployment secret.
5. Apply the additive database migration before production startup because production currently disables automatic migrations.

The app requests notification authorization only after sign-in and exposes a Settings shortcut to the operating-system notification settings. Firebase is used only as a push transport; Vita authentication remains unchanged.
