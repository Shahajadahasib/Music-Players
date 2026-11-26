# Architecture (Stage 2)

## Overview

```
lib/
├── config/app_config.dart        build-time config (--dart-define), no secrets
├── models/                       Song (+Playability), Playlist, UserData, Hive adapters
├── sources/                      MusicSource interface + Audius, Internet Archive, iTunes, Jamendo
├── search/                       TextNormalizer, TrackMatcher, SearchAggregator, MatchedTrack
├── playback/                     stream_verifier (is a stream really playable?),
│                                 fallback_planner (same-recording fallback),
│                                 error_gate (serialised, lossless error recovery)
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

Providers are asked **one at a time, in priority order** (Audius → Jamendo,
if licensed → Internet Archive). A later provider is only contacted when the
earlier ones could not supply what was asked for.

```
query ──► SearchAggregator.search
  ├─ cache hit (normalised query + enabled sources, 10 min)? → return
  ├─ identical search already running? → share it
  ├─ 1. catalogue metadata (iTunes), independent of playback discovery
  ├─ 2. pickReference: does the query name a specific song?
  │      • whole title + artist named ("perfect ed sheeran"), or
  │      • multi-word title clearly owned by one artist ("shape of you")
  │      • otherwise an open search ("lofi", "moonlight sonata")
  ├─ 3. full-track providers, sequentially (rate limit + 8 s timeout each;
  │      a newer query cancels before the next request)
  │      • named song: matchRecording → verify stream → STOP at the first
  │        verified exact original; else ask the next provider
  │      • open search: STOP at the first provider with relevant results
  └─ 4. rank: Best match first (verified original, or "Original recording
         unavailable" + store link); other recordings listed separately;
         likely re-uploads of the named artist's song by other accounts hidden
```

**Exact recording matching** (`TrackMatcher.matchRecording`) is rule-based.
The old 0.78 similarity threshold accepted same-title tracks by near-miss
artists ("Ed Sheeran Fan") and unknown artists, so it is now used only for
ranking. A candidate is the requested recording only if **all** of these hold:
- No version indicator the reference lacks and the query didn't ask for.
  These are rejected, not penalised: cover, tribute, violin/piano/guitar/cello…,
  instrumental, karaoke, remix, live, acoustic, sped up, slowed, nightcore,
  8-bit, lullaby and similar. Matching is whole-word, so "Alive" is not "live",
  and words in the real title ("Piano Man", "Live Your Life") are fine.
- Normalised titles are equal (≥ 0.92 for typos), so "Perfect Symphony" ≠ "Perfect".
- Both artists are known and the reference's primary artist is credited
  (featured artists and a "The" prefix may differ).
- Durations are within 8 s when both are reliable (never previews).

**Stream verification** (`HttpStreamVerifier`) runs before anything is called a
full track. It resolves the stream with the provider, then requests 2 bytes
(`Range: bytes=0-1`, following redirects). The result is *playable* only for
200/206 with an audio content type, and *unavailable* for 401/402/403/404/410/451
or non-audio. Timeouts and 5xx count as *unknown*, never playable. Results are
cached (30 min positive, 10 min negative), shared when in flight, and limited
to 3 checks at a time. Search badges show **Checking… → Full track /
Not verified / Not streamable**. On **web**, browsers hide cross-origin
response details (CORS), so a resolved URL counts as playable there and the
player load is the final check.

The 2-byte check is a fast **pre-filter**, not proof of playback. It proves
the provider granted access and returned audio, but not that the player can
decode the stream. So nothing is reported as playing until just_audio reports
`ready` + `playing`, and that is also the only point where a match is saved to
match memory. If the player then fails a stream, the controller calls
`StreamVerifier.markUnplayable`. That overrides the cached check and
invalidates cached discoveries, so the same dead stream isn't offered again.

`SearchAggregator.discover(reference)` uses the same sequential, verified
search for catalogue taps, album pages and playback fallback. Results are
cached and the remembered successful match (`MatchMemory`, Hive) is preferred,
but it is re-verified before reuse.

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
- **Failure recovery** (`FallbackPlanner`), always the *same recording*:
  1. Retry the same source once (from the same position if it had started).
  2. Try other known sources of the same recording, each verified first.
  3. Run sequential discovery on the next authorised providers.
  4. Stop playback and explain. It never moves on to a cover or another song by itself.

  Recovery runs through `SerialErrorGate`. An error raised while recovery is
  still switching sources is handled as soon as it finishes, not dropped.
  The "Switched to …" notice appears only once the new source has started.

  A 20-second stall is treated as a failure. Search results play only the
  tapped recording; they don't queue the rest of the result list.
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
