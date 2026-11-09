# Build, configuration and deployment

## 1. Prerequisites

- Flutter **3.47 stable** or newer (Dart ≥ 3.11). Check with `flutter --version`.
- Android: Android Studio / SDK 35+, JDK 17.
- iOS: macOS with Xcode 16+, CocoaPods, an Apple Developer account.
- Web: any static host with HTTPS (Firebase Hosting, Netlify, Cloudflare Pages, S3 + CloudFront).
- Licence server (only needed for web sales or server-side receipt checks): Docker, or the Dart SDK.

## 2. Configure the build

Copy `config/example.json` to `config/release.json` and fill it in. Everything in
it is **public**: it ends up inside the app.

| Key | Purpose |
|---|---|
| `APP_NAME` | Display name in the app (also update the Android label and iOS `CFBundleDisplayName`) |
| `AUDIUS_APP_NAME` | Unique app identifier sent to Audius |
| `ITUNES_COUNTRY` | Storefront for catalogue search |
| `ITUNES_PREVIEWS` | Leave `false` unless your lawyer is comfortable with promotional previews |
| `INTERNET_ARCHIVE` | Enable the PD / CC BY source |
| `JAMENDO_COMMERCIAL_AGREEMENT`, `JAMENDO_CLIENT_ID` | Only after you sign Jamendo's commercial agreement |
| `LICENSING_MODE` | `freemium` (free + Premium unlock) or `paid` (paid download, no purchase UI) |
| `PREMIUM_PRODUCT_ID` | Must match the product id in Play Console and App Store Connect |
| `LICENSE_PUBLIC_KEY` | From `server/bin/keygen.dart` (needed for web licence keys) |
| `LICENSE_SERVER_URL` | e.g. `https://licence.example.com` (optional on mobile) |
| `WEB_CHECKOUT_URL` | Stripe Payment Link / Checkout URL for web buyers |
| `PRIVACY_POLICY_URL`, `SUPPORT_EMAIL` | Shown in Settings. **Required by both stores** |

Every build command below takes `--dart-define-from-file=config/release.json`.

## 3. Android

1. **Change the application id.** `com.example…` is rejected by Google Play.
   In `android/app/build.gradle.kts`, set `namespace` and `applicationId`
   (e.g. `com.yourcompany.auroramusic`). Then move
   `android/app/src/main/kotlin/com/example/music_player_app/MainActivity.kt`
   to the matching package path and update its `package` line.
2. Create an upload keystore:
   `keytool -genkey -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
3. Create `android/key.properties` (git-ignored):
   ```
   storePassword=…
   keyPassword=…
   keyAlias=upload
   storeFile=upload-keystore.jks
   ```
   Without this file, release builds are signed with the debug key so they still
   build. **Never upload a debug-signed build.**
4. Build: `flutter build appbundle --release --dart-define-from-file=config/release.json`
5. Play Console:
   - Create the app and complete *Data safety* (see PRIVACY.md: no data collected
     by the developer; search terms go to the music providers).
   - Monetise → Products → **In-app products** → create `premium_lifetime`
     (non-consumable is the default for Play one-time products).
   - Add licence testers and test with an internal testing track.
   - Foreground service declaration: choose **Media playback**.
   - Notifications: media-session notifications are exempt from Android 13's runtime
     notification permission, so playback controls appear without a prompt.

## 4. iOS

1. In Xcode (`ios/Runner.xcworkspace`), set the **Bundle Identifier** and **Team**.
2. Capabilities: **In-App Purchase**. *Background Modes → Audio* is already in `Info.plist`.
3. App Store Connect → your app → **In-App Purchases** → *Non-Consumable* `premium_lifetime`. Add a review screenshot.
4. Agreements, Tax and Banking must be active (the **Paid Apps** agreement) or IAPs won't load.
5. Build: `flutter build ipa --release --dart-define-from-file=config/release.json`
6. Upload with Xcode Organizer or Transporter. Test the purchase in **TestFlight / Sandbox**.
7. App Review notes: explain that streams come from Audius / Internet Archive under
   their terms, and that Premium unlocks app features only.

## 5. Web

```bash
flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/release.json
```

- `--no-web-resources-cdn` bundles CanvasKit, so the app doesn't load code from Google's CDN.
- Deploy `build/web/` to any HTTPS static host. Set `Cache-Control: no-cache` for
  `index.html` and `flutter_service_worker.js`.
- **CORS:** the app calls the provider APIs directly from the browser. Audius,
  iTunes and archive.org currently allow cross-origin requests. If a provider
  changes that, route it through your own proxy.
- The Media Session API gives lock-screen and hardware-key controls in Chrome,
  Edge and Safari.
- Browsers can't keep picked local files between sessions. Re-open them each visit.

## 6. Licence server (web sales and receipt checks)

See `server/README.md`. Short version:

```bash
cd server
dart pub get
dart run bin/keygen.dart            # prints LICENSE_SIGNING_KEY + LICENSE_PUBLIC_KEY
docker build -t aurora-license .
docker run -p 8080:8080 -v aurora-data:/data --env-file .env aurora-license
```

Stripe: create a product with a **one-time price**, then a Payment Link whose
success URL points at your "licence" page, which calls
`GET /v1/licenses/checkout/{CHECKOUT_SESSION_ID}`. Add a webhook endpoint for
`checkout.session.completed` → `https://licence.example.com/v1/stripe/webhook`.

## 7. Before you ship (each release)

- `flutter analyze && flutter test` and `cd server && dart test` pass. CI does this, plus Android, iOS and Web builds.
- Run the manual device checklist in `docs/TESTING.md` on a real Android phone, a real iPhone, and Chrome and Safari.
- Review `docs/COMMERCIAL_CHECKLIST.md`.
