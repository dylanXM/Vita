# Vita AdMob setup

Backend and Admin deploy before the App. The database migration creates the
AdMob settings and reward tables with all formats disabled. The Admin page at
**Management → Google ads** controls rewarded ads, the credits-page banner,
post-purchase/post-credit-spend interstitials, subscriber visibility, reward
credits, daily reward limit, and Android/iOS ad unit IDs.

Before releasing the App:

1. Create Android and iOS apps in AdMob. Replace the sample iOS application ID
   in `app/ios/Flutter/Release.xcconfig`; set `VITA_ADMOB_ANDROID_APP_ID` for
   Android release builds. The sample application IDs are only for development.
2. Create separate rewarded, banner, and interstitial ad units for each platform.
   Enter their real IDs in Admin. Keep switches off until the App is released.
3. Enable server-side verification for both rewarded ad units with callback URL
   `https://vita-api.sweetai.work/v1/webhooks/admob/reward`. The backend verifies
   Google's ECDSA signature and ad unit, then grants the Admin-configured credits
   once per transaction. Client-side ad callbacks never grant credits.
4. Configure a privacy message in AdMob Privacy & messaging. The App requests
   consent before ads and shows an ad-privacy option in Settings when required.
5. Test with Google's test ad unit IDs on test devices. Do not use live units
   during development. Verify the rewarded callback, one ledger entry, the daily
   limit, and the subscriber display switch before enabling production ads.

Reward limits use UTC days. Banner ads are limited to the credits page.
Interstitials are considered after a successful store purchase or a new credit
debit in the server ledger and are locally capped at one every three minutes.
If no ad is available, purchases and credit actions continue normally.
