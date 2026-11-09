# Stage 1 — Technical audit of the original repository

Audited commit: `8f2ec54` ("Initial commit"), about 7,000 lines of Dart in 40 files.
I ran the audit with Flutter 3.47.9 (Dart 3.13): I read every file in `lib/`, ran
`flutter analyze` and ran `flutter test`.

## Summary

The original app was a well-built **single-provider demo**. It had a reasonable
foundation: Riverpod, one shared `just_audio` player, Hive persistence with
hand-written adapters, and a polished dark visual style. It was not close to a
sellable product. Several features were unreachable or fake, background playback
was not set up properly, and the only test failed.

| Area | Finding | Severity |
|---|---|---|
| Tests | The only test (`widget_test.dart`) **failed**. It looked for "Your Music / Discover / Favorites / Playlists" tabs that no longer existed. | High |
| Fake feature | `LyricsScreen` showed **made-up placeholder lyrics** for every song, "synced" by position percentage. | High (misleading to customers) |
| Unreachable features | `SearchScreen`, `PlaylistDetailScreen` and `PremiumDiscoverTab` were never navigated to. Users could create playlists from the player but **could never open them**. Favourites could be added but there was no favourites screen. | High |
| Background playback | No `audio_service` / `just_audio_background`. That meant no media notification, no lock-screen or Bluetooth controls, and no Android foreground service, so playback is killed in the background on modern Android. | High |
| Release build | `android/app/build.gradle.kts` force-cast `key.properties` values even when the file was missing, so `flutter build apk --release` failed for anyone without the keystore. | High |
| Playback errors | One generic error message. There was no retry, no fallback, and a failed track stalled the queue. | High |
| Search | Audius only, first-result order, no matching across providers, and a cache that held only the last query. | High (product goal) |
| Licensing | `JamendoService` and a **hard-coded Jamendo client id** existed but were unused. Jamendo's free API is non-commercial, so it could not have been used in a paid app anyway. | Medium |
| Misleading UI | "Made For You" was every third cached song and "Trending" was the first 12 cached songs. The labels didn't match the content. | Medium |
| Controls | The controller supported shuffle and repeat but the UI exposed neither. No queue view, no volume, no sleep timer. | Medium |
| Seek bug | Seeking was clamped to `state.duration`. Before the duration was known (0), every seek went to 0:00. | Medium |
| Interruptions | The controller paused on audio-focus interruptions *as well as* just_audio's own handling. That stopped playback from resuming automatically after phone calls. | Medium |
| Publishing | `applicationId` / bundle id `com.example.music_player_app` and label `music_player_app`. The Play Store rejects `com.example`. | Medium (release blocker) |
| Theming | Dark only, with colours hard-coded as static constants throughout the widgets. | Low |
| Privacy / offline | `google_fonts` downloads fonts at runtime from Google, and Flutter web loaded CanvasKit from Google's CDN. | Low |
| Hygiene | No CI and no input validation (e.g. playlist name length). Unused `ApiClient`. | Low |

`flutter analyze` itself reported only one lint (`use_key_in_widget_constructors`).
The problems were in behaviour, not syntax.

## What was preserved

- **Hive storage and adapters.** I extended them backwards-compatibly, so v1 libraries
  still load (covered by `test/models/storage_test.dart`).
- **Playlist CRUD, favourites, and restoring the last song and position** with
  throttled position saves.
- **The single shared `AudioPlayer`** and the idea of a buffering-stall timer
  (which now triggers source fallback instead of only showing an error).
- **Audius parsing** (moved into `AudiusSource`, plus gated-content filtering).
- **UI building blocks**: `ArtworkImage` caching, `PressableScale`,
  `StaggeredListEntrance`, `NewPlaylistDialog`, `AuroraScrollBehavior`, and the
  "Aurora" visual identity (now a dark + light palette).

## What was removed and why

| Removed | Reason |
|---|---|
| `lyrics_screen.dart` | Fabricated lyrics. Lyrics need a licensed provider (see LIMITATIONS.md). |
| `search_screen.dart` (local filter), `discover_tab.dart` | Unreachable. Replaced by the multi-provider Search tab. |
| `audius_service.dart`, `jamendo_service.dart`, `utils/api_config.dart` | Replaced by the `MusicSource` provider layer. The hard-coded Jamendo id is gone. |
| Old home, player, mini player and tile widgets | Rebuilt as theme-aware screens with real data and accessibility labels. |

## Prioritised plan that was executed

1. Make it build and test reliably: fix release signing and the failing test, and add CI.
2. Provider abstraction plus licensing gates, so only authorised sources can stream.
3. Multi-provider search with normalisation, matching, ranking, caching and rate limits.
4. Audio engine: background and lock screen, fallback, queue, sleep timer, metrics.
5. Navigation and library so every feature is reachable; remove fake features.
6. One-time purchase and licence system, with a backend for web purchases and receipt checks.
7. Tests, documentation, and release and compliance checklists.
