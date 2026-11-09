# Testing and QA

## Automated tests

Run with `flutter test` (app, 76 tests) and `cd server && dart test` (licence server, 9 tests).
No test touches the network. Provider responses are synthetic fixtures shaped like
each provider's documented format, and they are only used in tests.

| Area | File | What it proves |
|---|---|---|
| Normalisation & matching | `test/search/matching_test.dart` | feat./remaster/bracket stripping; "Stay With Me" keeps "with"; live/karaoke/cover ≠ original; same title by another artist ≠ match; duration bands; previews ignore duration; typo tolerance; relevance ranking and remix penalty |
| Multi-provider search | `test/search/search_aggregator_test.dart` | concurrent search + cross-provider merge with catalogue metadata; full > preview > none ranking; doesn't pick the first responder; one provider failing or timing out doesn't break search; offline detection; cache, TTL, in-flight de-duplication; failed searches not cached; rate limiting; remembered matches; `findPlayableFor` only accepts confident matches and skips metadata providers |
| Fallback | `test/playback/fallback_planner_test.dart` | order: known candidates → fresh search → give up; never a different recording; single same-source retry; local files have no fallback; offline lookup is safe; attempt cap |
| Provider integrations | `test/sources/sources_test.dart` | Audius gated/non-streamable filtering, `app_name`, 429 handling; iTunes metadata-only by default and previews only when enabled; IA commercial-licence filter, NC rejection and MP3 resolution; Jamendo gating and parsing; API client retry, 4xx no-retry, timeout, bad JSON |
| Licensing | `test/licensing/licensing_test.dart` | Ed25519 key round trip; tamper, foreign-signer, wrong-product and garbage rejection; **shared test vector with the server**; purchase → premium → persisted; server reject vs outage; cancel/error; restore; key activation and re-validation; deactivate; paid-upfront mode |
| Storage | `test/models/storage_test.dart` | **v1 → v2 Hive migration** (old libraries still load); history order and cap; playlist CRUD and reorder; settings and match memory; delete-all-data |
| UI | `test/widgets/app_test.dart` | boot + navigation + featured data; search with honest availability badges; catalogue-only tap explains and links out instead of playing something else; free-plan gating (4th playlist, light theme); invalid licence key; Premium light theme |
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
- [ ] Airplane mode mid-song: the buffered part plays, then the app retries/falls back and finally shows Retry. Turning the network back on and pressing Retry resumes.
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

- `flutter analyze`: no issues. `flutter test`: 76 passed. Server `dart test`: 9 passed.
- `flutter build web --release --no-web-resources-cdn`: success. The built app was
  loaded in headless Chromium at phone and desktop sizes. Home, offline state,
  search and cross-provider merging rendered correctly with intercepted fixture
  responses (the sandbox had no access to the provider APIs).
- **Not verified here:** Android/iOS builds and real playback (no Android SDK, no
  macOS, and no network access to providers in this environment). The CI workflow
  builds Android and iOS on GitHub's runners.
