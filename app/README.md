# Vita — AI Companion mobile app

Flutter client for the Vita backend (Go). WeChat-style interaction mindset:
Chat | Life | Memories | Me, white surfaces, green accent, message bubbles.

## Run

```bash
flutter pub get
flutter run --dart-define=VITA_API_BASE_URL=http://127.0.0.1:8260
```

Keys are injected at build time with `--dart-define` and default to empty
placeholders so the app compiles and runs before the accounts exist.

| Define | Purpose |
| --- | --- |
| `VITA_API_BASE_URL` | Backend base URL (default `http://127.0.0.1:8260`) |
| `VITA_REVENUECAT_KEY` | RevenueCat **public SDK key** (subscriptions + credit packs) |
| `VITA_GOOGLE_SERVER_CLIENT_ID` | Google OAuth **web client ID** (needed on Android for an ID token) |

## Login / register

- **Email**: enter an email → get a 6-digit code → the backend auto-creates the
  account on first use (`/v1/auth/send-code` + `/v1/auth/app/login`).
- **Google**: `google_sign_in` returns an ID token which the Go backend verifies
  against Google's JWKS (`/v1/auth/google`) — no Firebase.

Platform setup for Google sign-in:

- **iOS**: add `GoogleService-Info.plist` to `ios/Runner` and the reversed client
  ID URL scheme to `Info.plist` (`CFBundleURLTypes`).
- **Android**: put `google-services.json` in `android/app` and pass the web
  client ID via `VITA_GOOGLE_SERVER_CLIENT_ID`.

## Subscriptions & credits (RevenueCat)

1. Create the products in RevenueCat / App Store Connect / Play Console:
   - `vita.plus.monthly` — US$9.99/month, entitlement `plus`.
   - `vita.plus.yearly` — US$79.99/year, entitlement `plus`.
   - `vita.premium.monthly` — US$19.99/month, entitlement `premium`.
   - `vita.premium.yearly` — US$159.99/year, entitlement `premium`.
   - Consumables `vita.coins.100` (US$1.99), `vita.coins.500` (US$7.99), and
     `vita.coins.1200` (US$14.99).
   Use the same product IDs for the iOS and Android RevenueCat products. Store
   prices remain authoritative and may be localized by Apple or Google.
2. Point the RevenueCat webhook at `POST {API}/v1/webhooks/revenuecat` with the
   shared secret in the `Authorization: Bearer ...` header
   (`VITA_REVENUECAT_WEBHOOK_SECRET` on the backend).
3. On purchase/renewal the backend grants the monthly credit allowance
   (`VITA_SUBSCRIPTION_CREDITS_MONTHLY`, default 500) and records a
   `credit_transactions` row. Grants are idempotent (webhook-retry safe).

The Stripe side (`/v1/stripe/checkout`, `/v1/webhooks/stripe`) serves the web /
admin product only — in-app digital goods must go through the store (RevenueCat).

## Project layout

```
lib/
  core/        constants, dio client, token storage, theme, bootstrap
  features/
    auth/      login/register (email + Google), splash gate
    shell/     bottom tabs: Chat | Life | Memories | Me
    chat/      companion list + chat page
    companion/ companion creation form
    life/      today's life timeline
    memories/  shared memories
    me/        profile, subscription & credits entries
    billing/   RevenueCat subscription + credits pages
  shared/      avatar, empty state, list tile, formatters
```

## Tests

```bash
flutter analyze
flutter test
```
