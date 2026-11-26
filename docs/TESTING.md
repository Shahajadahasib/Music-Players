# Testing and QA

## Automated tests

Run with `flutter test` (app, 120 tests) and `cd server && dart test` (licence server, 9 tests).
No test touches the network. Provider responses are synthetic fixtures shaped like
each provider's documented format, and they are only used in tests.

| Area | File | What it proves |
|---|---|---|
| Normalisation & ranking helpers | `test/search/matching_test.dart` | feat./remaster/bracket stripping; "Stay With Me" keeps "with"; version-tag extraction; artist credit splitting; `relevance` used for *ordering* results (the legacy `sameSong` score is kept only for ranking and is no longer used to accept a stream) |
| Exact recording matching | `test/search/matching_test.dart` (`matchRecording`) | exact original; wrong / near-miss / missing artist; violin, piano, instrumental, karaoke, remix, live, sped up, nightcore, tribute rejected; similar titles rejected; duration mismatch; versions allowed only when requested; "Piano Man", "Live Your Life", "Alive" not misread |
| Sequential search & discovery | `test/search/search_aggregator_test.dart` | providers asked one at a time, never all at once; metadata first; stop at the first verified original (later providers get **0 requests**); next provider only when needed; failed verification → same recording elsewhere; open searches stop at the first relevant provider; timeout and rate limit; cancellation sends no further requests; cached discovery reused but not when the stream is known gone, or after the **player** failed it (next source of the same recording found); which queries name a specific song (`pickReference`); one provider failing doesn't break search; offline detection; failed searches not cached; featured interleaving; "original unavailable"; likely re-uploads hidden; catalogue duplicates folded |
| Stream verification | `test/playback/stream_verifier_test.dart` | 206 audio → playable (2-byte range request); 403/404/410 and HTML → unavailable; timeout/5xx → unknown; caching and in-flight sharing; web mode; a real player failure overrides a cached "playable" check |
| Recovery serialisation | `test/playback/error_gate_test.dart` | an error raised while recovery is switching sources is handled afterwards, not dropped; only the latest pending error is kept; a failing recovery still releases the gate |
| Fallback | `test/playback/fallback_planner_test.dart` | retry same source once → verified known sources of the same recording → sequential discovery → stop with explanation; never a cover / instrumental / other artist; known-dead streams not retried; local files; offline; attempt cap |
| Provider integrations | `test/sources/sources_test.dart` | Audius gated/non-streamable filtering, `app_name`, 429 handling; iTunes metadata-only by default and previews only when enabled; IA commercial-licence filter, NC rejection and MP3 resolution; Jamendo gating and parsing; API client retry, 4xx no-retry, timeout, bad JSON |
| Licensing | `test/licensing/licensing_test.dart` | Ed25519 key round trip; tamper, foreign-signer, wrong-product and garbage rejection; **shared test vector with the server**; purchase → premium → persisted; server reject vs outage; cancel/error; restore; key activation and re-validation; deactivate; paid-upfront mode |
| Storage | `test/models/storage_test.dart` | **v1 → v2 Hive migration** (old libraries still load); history order and cap; playlist CRUD and reorder; settings and match memory; delete-all-data |
| UI | `test/widgets/app_test.dart` | boot + navigation + featured data; search with verified "Full track" badges and provider names; catalogue-only tap explains ("Original recording unavailable") and links out instead of playing something else; named song with no original → Best match unavailable, violin cover listed separately and never played; stream checks only for rows on screen; library regression (favourites and playlist screens show saved songs); free-plan gating (4th playlist, light theme); invalid licence key; Premium light theme |
| Server | `server/test/server_test.dart` | wire format pinned; Stripe signature (valid, tampered, stale, missing); webhook → key issued once, retrievable, e-mail hashed; store verdict mapping; input validation |

## What automated tests cannot cover (manual checklist)

Real playback, OS media controls and store purchases need real devices and store
sandboxes. Run this before each release.

### Android (physical phone, Android 10 and 14+)
- [ ] Search "lofi" → tap a result → audio starts. Note the start time in Settings → Diagnostics.
- [ ] Lock the screen: notification and lock-screen controls work (play/pause/next/previous/seek).
- [ ] Switch apps for 10 minutes: playback continues.
- [ ] Bluetooth headset: play/pause/next buttons work. Disconnecting the headset pauses playback.
- [ ] Incoming call: pauses, then resumes after the call. A navigation prompt ducks the volume.
- [ ] Airplane mode mid-song: the buffered part plays, then the app retries the same source once, tries other sources of the **same recording**, and finally stops with an explanation and Retry (it never jumps to another song). Turning the network back on and pressing Retry resumes.
- [ ] Search "perfect ed sheeran": Best match shows "Original recording unavailable." with an Apple Music link; tapping it plays nothing.
- [ ] Search a song that exists on Audius: Best match shows "Full track · Audius" and plays.
- [ ] Queue: Play next, Add to queue, reorder, swipe to remove, shuffle, repeat one/all.
- [ ] Sleep timer: 5 minutes, and "end of this song".
- [ ] Local files (Premium): add an MP3, restart the app, it still plays.
- [ ] IAP with a licence tester: buy, then uninstall/reinstall, then **Restore purchase**.
- [ ] Release build (`appbundle`) installs from the internal testing track.

### iOS (physical iPhone)
- [ ] Same playback, lock-screen / Control Center, AirPods, call-interruption and network checks as Android.
- [ ] Silent switch on: music still plays (playback audio category).
- [ ] Sandbox purchase, then delete the app, reinstall and restore.
- [ ] TestFlight build passes App Store Connect processing.

### Web (Chrome, Safari, Firefox; desktop and mobile)
- [ ] Search, play, seek, next. Media keys and the OS media overlay (Chrome/Edge/Safari) work.
- [ ] Desktop width shows the side navigation rail. Phone width shows the bottom bar.
- [ ] Buy through `WEB_CHECKOUT_URL` → the success page shows a key → paste it → Premium.
- [ ] Reload: Premium persists. "Delete all my data" keeps the licence.
- [ ] Throttle to "Slow 3G" in DevTools: skeletons, then results. Offline: error states with Retry.

## Performance

- Diagnostics (Settings) report median tap-to-audio time, rebuffers, fallbacks and failures per device.
  Record them for each release on a mid-range Android phone over 4G and Wi-Fi.
- Targets (guidance): median start < 1.5 s on Wi-Fi; < 1 rebuffer per hour on stable 4G.
- `flutter run --profile` + DevTools: scrolling the search results should stay at 60 fps
  (position ticks only rebuild the seek bar and mini progress through `select`).

## Verified while building this version

- `flutter analyze`: no issues. `flutter test`: 120 passed. Server `dart test`: 9 passed.
- GitHub Actions (Flutter pinned to 3.47.9): analyze + tests + Web build, Android
  release APK, iOS release build (no codesign) and licence-server tests all pass.
- Live provider checks (Audius, iTunes, Internet Archive) from the build environment:
  - "perfect ed sheeran" asked iTunes → Audius → Archive and showed "Original recording unavailable".
  - "lofi" stopped after Audius.
  - A real Audius original was found on Audius alone and its stream returned HTTP 206 audio.
- `flutter build web --release --no-web-resources-cdn`: success. The built app was
  driven in headless Chromium at phone and desktop sizes against the live APIs.
- **Not verified here:** playback, lock-screen controls and purchases on physical
  Android and iOS devices. Run the manual checklist above.
