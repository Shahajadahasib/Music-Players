# Aurora Music

A premium Flutter music player for **Android, iOS and Web**. Search once: the
app queries several legitimate music services at the same time, works out which
results are the same song, and plays the **best authorised source**. If a stream
fails, it switches to another authorised source automatically.

Sold as a **one-time purchase**: a free tier plus a Premium unlock through the
App Store or Google Play in-app purchase, or a licence key on the web. You can
also sell the app itself as a paid download. There is no subscription.

> Working name and icon are placeholders. See `docs/COMMERCIAL_CHECKLIST.md`
> before selling.

## Features

| | |
|---|---|
| 🔎 Multi-provider search | Concurrent search across Audius, Internet Archive (PD / CC BY) and Apple's catalogue. Normalisation, duplicate merging, confidence-scored matching, availability-aware ranking, caching, rate limiting |
| 🎯 Honest availability | Every result is badged *Full track*, *Preview* or *Not streamable*. The app never plays a different recording (cover, karaoke, live) in place of the one you chose |
| ▶️ Reliable playback | Fast start (tuned buffers), next-track pre-buffering, background playback, lock-screen / notification / Bluetooth / headset controls, audio-focus handling, automatic source fallback, stall detection |
| 🎛 Player | Queue (play next, add, reorder, remove), shuffle, repeat one/all, seek with buffered indicator, volume, sleep timer |
| 📚 Library | Favourites, playlists (create / rename / reorder / delete), recently played and history, artist and album pages, music files from your device |
| 🎨 Design | Original "Aurora" design, dark and light themes, responsive (bottom bar on phones, side rail on tablets and desktop web), skeletons, empty and error states, accessibility labels |
| 💳 Commercial | One-time Premium (IAP on mobile, Ed25519 licence keys on web), restore purchases, optional server verification, a licence server with Stripe webhook |
| 🔒 Privacy | No account, no analytics, library kept on the device, secure storage for the entitlement, delete-all-data |

## Quick start

```bash
flutter pub get
flutter run -d chrome                     # or an Android / iOS device
flutter run --dart-define-from-file=config/example.json
```

Tests:

```bash
flutter analyze && flutter test           # app
(cd server && dart pub get && dart test)  # licence server
```

The default build needs **no API keys**. Audius, Internet Archive and the iTunes
Search API are keyless. Accounts you'll need for selling:

| Account | For | Where |
|---|---|---|
| Google Play Console | Android release + in-app product `premium_lifetime` | play.google.com/console |
| Apple Developer + App Store Connect | iOS release + non-consumable `premium_lifetime` | developer.apple.com |
| Stripe | Web licence sales | stripe.com |
| Audius API key (optional, recommended) | Higher limits and an identified app | api.audius.co/plans |
| Jamendo commercial licence (optional) | Enabling Jamendo as a source | licensing@jamendo.com |

## Documentation

| Doc | Contents |
|---|---|
| [docs/AUDIT.md](docs/AUDIT.md) | Stage 1 audit of the original code: bugs, fake or unreachable features, what was kept |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Architecture, search/matching pipeline, audio engine, licensing design, backend vs on-device |
| [docs/PROVIDER_LICENSING.md](docs/PROVIDER_LICENSING.md) | **Provider licensing matrix** and API integration details |
| [docs/COMMERCIAL_CHECKLIST.md](docs/COMMERCIAL_CHECKLIST.md) | Licensing, store, payment and privacy compliance checklist |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Configuration and Android / iOS / Web / server build and release steps |
| [docs/TESTING.md](docs/TESTING.md) | Automated test coverage and the manual device checklist |
| [docs/LIMITATIONS.md](docs/LIMITATIONS.md) | Remaining limitations and third-party costs |
| [PRIVACY.md](PRIVACY.md) | Privacy policy template |
| [server/README.md](server/README.md) | Licence server |

## Project layout

```
lib/
  config/       build-time configuration (public values only)
  sources/      provider integrations (MusicSource)
  search/       normalisation, matching, aggregation
  playback/     fallback planning
  services/     audio engine, storage, local files, HTTP, error reporting
  controllers/  PlayerController (Riverpod)
  licensing/    one-time purchase & licence keys
  providers/    Riverpod wiring
  theme/        dark/light design system
  ui/           shell, screens, widgets
server/         licence server (Dart)
test/           unit + widget tests
```

## Important: what users can stream

Free APIs that permit commercial apps **do not include full-length mainstream
major-label music**. Aurora streams independent and artist-published music
(Audius) and public-domain or CC-licensed recordings (Internet Archive) at full
length. Mainstream songs are identified with Apple catalogue data and offered as
an "Open in Apple Music" link. Details and options are in
[docs/PROVIDER_LICENSING.md](docs/PROVIDER_LICENSING.md).
