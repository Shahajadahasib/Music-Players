# Architecture (Stage 2)

## Overview

```
lib/
├── config/app_config.dart        build-time config (--dart-define), no secrets
├── models/                       Song (+Playability), Playlist, UserData, Hive adapters
├── sources/                      MusicSource interface + Audius, Internet Archive, iTunes, Jamendo
├── search/                       TextNormalizer, TrackMatcher, SearchAggregator, MatchedTrack
├── playback/fallback_planner.dart  what to play when a stream fails
├── services/                     AudioService (just_audio), Hive storage, local files, API client, ErrorReporter
├── controllers/                  PlayerController (Riverpod StateNotifier) + state
├── licensing/                    licence keys (Ed25519), store gateway (IAP), LicenseController
├── providers/                    Riverpod wiring: sources, settings, player
├── theme/                        Aurora dark/light palette (ThemeExtension), typography
└── ui/                           AppShell (tabs + mini player) and screens/widgets
server/                           Dart licence server (Stripe webhook, store verification)
```

**State management:** Riverpod 2 (`StateNotifier`). The player state is one
immutable object, and widgets subscribe with `select(...)` so a position tick
only rebuilds the seek bar and mini progress bar.

**Persistence:** Hive (works on Android, iOS and Web/IndexedDB). It holds
songs, playlists, favourites, history (capped at 500), settings, recent searches
and match memory. The Premium entitlement is stored separately in
`flutter_secure_storage` (Keychain / Android Keystore / WebCrypto).

## Search and matching pipeline

```
query ──► SearchAggregator.search
           ├─ cache hit? (normalised query + enabled sources, 10 min TTL, LRU 60)
           ├─ identical search already in flight? → share it
           ├─ per-source rate limiter (iTunes 18/min)
           ├─ Future.wait(all enabled sources, 8 s timeout each, errors isolated)
           ├─ interleave results (every provider's top hits first)
           ├─ cluster: TrackMatcher.sameSong ≥ 0.78 → same recording
           ├─ per cluster: display = catalogue (iTunes) metadata if present
           │               candidates = playable versions, full > preview,
           │               remembered match first, then provider priority
           └─ rank: 0.75·relevance + availability (full .25 / preview .12 / none 0)
                    + small provider-rank bonus; drop relevance < 0.3
```

`TrackMatcher.sameSong` combines title similarity (token Jaccard or Levenshtein
ratio after normalisation), artist similarity (best pair over split credits),
and duration (±3 s / 10 s / 30 s bands, ignored for previews). It **penalises
version mismatches** (live, remix, karaoke, cover, sped-up…), so a karaoke
cover is never treated as the original.

`findPlayableFor(reference)` searches **full-track providers only**, so it
doesn't spend iTunes' rate limit. It returns candidates that clear the match
threshold, and is used for catalogue-only taps, album pages and fallback.

## Audio engine

- **One `AudioPlayer`** (just_audio 0.10), playlist API (`setAudioSources`,
  `insert/remove/moveAudioSource`), and lazy preparation so the next track
  pre-buffers.
- **Buffering:** Android `LoadControl` starts playback after 1.5 s buffered
  (default 2.5 s) and keeps up to 50 s. iOS waits to minimise stalling with a
  30 s forward buffer.
- **Background, lock screen, Bluetooth, headset:** `just_audio_background`
  (audio_service). Android uses a foreground media service and
  `AudioServiceActivity`. iOS uses `UIBackgroundModes=audio`. Web uses the
  browser Media Session.
- **Audio focus and interruptions:** handled by just_audio. It pauses for calls,
  ducks for navigation prompts, resumes afterwards, and pauses when headphones are
  unplugged.
- **Failure recovery** (`FallbackPlanner`):
  1. If a stream drops mid-song, retry the same source once from the same position.
  2. Try other candidates already known from the search.
  3. Run a fresh confidence-checked search on other authorised providers.
  4. Skip to the next track and tell the user, or stop with a retry action.

  A 20-second stall is treated as a failure.
- **Metrics (local only):** time from tap to audio (median of the last 50),
  rebuffer events, fallbacks and failed tracks. Shown in Settings → Diagnostics.

## Licensing / purchase design

| Platform | Mechanism | Verification |
|---|---|---|
| Android | Google Play in-app product (non-consumable) via `in_app_purchase` | The store result is trusted on device. If `LICENSE_SERVER_URL` is set, the server also checks it with the Google Play Developer API |
| iOS | App Store non-consumable via `in_app_purchase` | The store result is trusted. Optional server check via the App Store Server API |
| Web | Stripe Checkout → licence server issues `AURORA1.…` key → user pastes it | Ed25519 signature checked **offline** with the embedded public key |
| Any | `LICENSING_MODE=paid` (sell the app itself as a paid download) | No purchase UI. Everything unlocked |

Design choices:
- **No subscription.** One non-consumable product. "Restore purchase" is available on stores.
- **Never lock out legitimate users.** The entitlement is cached in secure storage
  and trusted offline. If the verification server is down, the purchase is accepted
  provisionally. Only a definitive "invalid" answer from the server refuses it.
- **No secrets in the client.** The app embeds only the *public* verification key.
  Signing keys, Stripe secrets and store credentials live only on the server.
- Free plan: search, full streaming, queue, favourites, history and 3 playlists.
  Premium: unlimited playlists, on-device files, sleep timer, light and system
  themes. This is configured in `PremiumFeature` / `AppConfig.freePlaylistLimit`.

## What needs a backend and what runs on the device

| Feature | Where |
|---|---|
| Search, matching, ranking, caching, playback, fallback, library, playlists, history, settings, local files, diagnostics | **On device** (no backend) |
| Android / iOS purchase | On device via the store. *Optional* server re-verification (recommended against fraud, needs store credentials) |
| Web purchase | **Backend required**: Stripe webhook → signed licence key (`server/`) |
| Licence revocation (refunds, chargebacks) | Backend (`/v1/licenses/revoked` is served; the app does not poll it yet, see LIMITATIONS.md) |
| Provider API keys that must stay secret | Backend proxy. None of the integrated providers needs one today; Jamendo's `client_id` is a public identifier |
| Crash reporting | Optional third-party service (see below) |

## Crash reporting and analytics

`ErrorReporter` catches Flutter, platform and zone errors. It logs locally and
keeps the last 50 in memory. By default **nothing leaves the device**. To add
Sentry or Crashlytics, assign `ErrorReporter.sink` in `main()`. Send stack
traces only; never send search terms or file names. Update PRIVACY.md if you do.

There is no analytics SDK. The performance metrics are local-only by design.

## Accessibility

- Semantic labels on custom controls (play/pause, badges, equaliser, artwork) and headers.
- Tooltips on every icon button. Slider value announcements for seek and volume.
- Text uses the theme `TextTheme`, so system font scaling applies.
- Dark and light palettes chosen for contrast (body text ≥ 4.5:1 on the background).
- Wide layouts switch to a `NavigationRail` (≥ 840 px) for keyboard and mouse use on the web.

## Key packages

| Package | Why |
|---|---|
| `just_audio` + `just_audio_background` | Mature cross-platform playback with playlists, buffering control and system media integration |
| `flutter_riverpod` | Kept from the original. Testable overrides |
| `hive_flutter` | Kept. Works on Web. Fast |
| `in_app_purchase` | Official Flutter plugin for Play and App Store |
| `flutter_secure_storage` | Platform keystore for the entitlement |
| `cryptography` | Ed25519 that runs on every platform, including Web |
| `file_picker`, `path_provider` | Importing local files |
| `url_launcher` | "Open in…" provider and store links |
| `cached_network_image` | Artwork cache |
