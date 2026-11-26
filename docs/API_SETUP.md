# API setup: providers, keys and build flags

All configuration is passed at build time:

```bash
flutter run --dart-define=YOUTUBE_API_KEY=... --dart-define=RADIO=true
```

You can also put the values in a file:

```bash
flutter build apk --dart-define-from-file=config/release.json
```

**Nothing compiled into a Flutter app is secret.** The app bundle can be
unpacked, so only *public client identifiers* belong here. Keep the
`config/*.json` files with real values out of git (they are git-ignored).
Server secrets (Spotify client secret, Stripe keys, store service accounts)
live only on a backend, such as `server/`.

## Providers

| Flag | Default | Effect |
|---|---|---|
| `AUDIUS_APP_NAME` | `aurora-music-player` | Identifies the app to Audius (requested by Audius) |
| `AUDIUS_API_HOST` | `api.audius.co` | Audius API host |
| `INTERNET_ARCHIVE` | `true` | Internet Archive CC0/PD/CC BY/BY-SA audio |
| `ITUNES_METADATA` | `true` | Apple catalogue metadata to identify songs |
| `ITUNES_PREVIEWS` | `false` | Allow 30 s Apple previews (shown with "Open in Apple Music") |
| `ITUNES_COUNTRY` | `US` | Storefront (`BD` and `IN` help Bangla coverage) |
| `JAMENDO_CLIENT_ID` | — | Jamendo client id (devportal.jamendo.com) |
| `JAMENDO_COMMERCIAL_AGREEMENT` | `false` | Set `true` **only** with a signed Jamendo commercial licence |
| `FREETOUSE_COMMERCIAL_LICENSE` | `false` | Set `true` **only** with a paid Free To Use Commercial plan |
| `MUSICBRAINZ_ENABLED` | `false` | MusicBrainz metadata. Commercial apps need a MetaBrainz plan. |
| `MUSICBRAINZ_CONTACT` | `support@example.com` | Contact sent in the MusicBrainz User-Agent (required by their rules); set your own |
| `YOUTUBE_API_KEY` | — | Enables "Open in YouTube" (the official player only) |
| `RADIO` | `true` | Live radio screen (Radio Browser) |
| `PROVIDER_PRIORITY` | `audius,jamendo,freetouse,archive` | Order in which full-track providers are asked |

A provider that is built in can still be switched off by the user in
**Settings → Music sources**.

## YouTube key

1. Create a project at console.cloud.google.com and enable **YouTube Data API v3**.
2. Create an API key and restrict it:
   - Android: package name plus SHA-1.
   - iOS: bundle id.
   - Web: HTTP referrers.
   - API restriction: YouTube Data API v3 only.
3. Build with `--dart-define=YOUTUBE_API_KEY=...`.

Each search costs 100 quota units out of the default 10,000 per day. The app
only asks YouTube after every in-app source has failed for a specific song.

## Provider order

`PROVIDER_PRIORITY` lists provider ids, separated by commas. Providers that
are not listed keep their built-in order after the listed ones. For example,
to prefer the Internet Archive:

```bash
--dart-define=PROVIDER_PRIORITY=archive,audius
```

The order only matters *within* a provider kind:
- **Metadata** providers are asked first, to identify the song.
- **Full-track** providers are asked one at a time.
- **External players** are asked last, and only when nothing plays in-app.
- **Radio** is never part of song search.

## Keys you will NOT find here

| Key | Why |
|---|---|
| `SPOTIFY_CLIENT_ID` / `SPOTIFY_CLIENT_SECRET` | Spotify is not integrated (see the research doc). If it is added later, the secret goes on a backend. |
| `LASTFM_API_KEY` | Last.fm needs commercial permission; it is not integrated. |
| `FREESOUND_TOKEN` | Freesound is not integrated (sound effects; commercial agreement needed). |
| `AUDIUS_API_KEY` | Audius read endpoints don't need one. |

## Adding a provider

1. Implement `MusicSource` in `lib/sources/`.
2. Declare its `SourceInfo`:
   - `kind`
   - `capabilities`
   - `commercialStatus`
   - `perTrackLicence`
   - `experimental`
3. Give it a flag in `AppConfig`, and register it in `availableSourcesProvider` behind that flag.
4. Add mocked parser tests in `test/sources/` and optionally a live check in `test_live/`.
5. Document it in `docs/MUSIC_PROVIDER_RESEARCH.md`.
