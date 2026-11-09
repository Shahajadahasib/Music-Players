# Music providers: API integration and licensing matrix

> **This is not legal advice.** It is an engineering summary of public terms as
> I could check them in November 2026. Terms change. **Before you launch, have a
> lawyer review each provider's current terms, and get written confirmation from
> the provider where this document says "verify".**

## Key principle

Permission to *call an API* is not permission to *sell access to the music* it
returns. This app is sold once. Premium unlocks **app features**, not music. All
streaming is free to the user and comes from providers whose terms allow
third-party apps to stream it. A provider that cannot support this model is
either left out or used **only for metadata or links**.

## Licensing matrix

| Provider | In app as | Full tracks | Previews | Commercial use of the app | Key / auth | Rate limits | Caching / redistribution | Attribution | Status |
|---|---|---|---|---|---|---|---|---|---|
| **Audius** | Full-track source (default on) | ✅ Artist-published streams | – | API Terms + Open Music Licence (July 2025) govern third-party apps. **Verify** that a paid app is allowed | None for read endpoints. `app_name` requested. An API key is optional (api.audius.co/plans) | Not published for the free tier. Be conservative | Stream only. Never download or re-host. Gated tracks (`stream_conditions`) are excluded | Show "Audius" and the artist. Link to the track | ✅ Integrated. ⚠ Verify terms |
| **Internet Archive** | Full-track source (user-toggleable) | ✅ Only items labelled public domain / CC0 / CC BY / CC BY-SA | – | Allowed by those licences. **Uploader-declared, not verified by the Archive** | None | Be polite. Metadata calls are cached in memory | Stream from archive.org. Honour takedowns | CC BY / BY-SA require credit (title, creator, licence link). The app shows the licence | ✅ Integrated with licence filter |
| **iTunes Search API** | Catalogue metadata + "Open in Apple Music" | ❌ | 30 s, **only to promote store content** | Metadata use is common. Previews are promotional only | None | ≈20 requests/min per client (enforced in the app at 18/min) | Apple asks heavy users to cache (done: 10 min) | "Song information from Apple". Link to the store | ✅ Metadata only (previews off by default; `ITUNES_PREVIEWS=true` is at your own risk) |
| **Jamendo** | Full-track source, **off** | ✅ CC-licensed MP3 | – | ❌ The free API is **non-commercial only**. A commercial quote is needed from licensing@jamendo.com | `client_id` | Per plan | Per agreement and per track's CC licence (NC tracks also restrict use) | Jamendo + artist + CC licence | ⛔ Code ready. Enabled only with `JAMENDO_COMMERCIAL_AGREEMENT=true` + `JAMENDO_CLIENT_ID` |
| **Deezer** | Not integrated | ❌ (30 s previews) | 30 s | ❌ Deezer's developer FAQ: commercial use needs a **commercial agreement** | App id / OAuth | 50 req / 5 s | Per agreement | Deezer branding | ⛔ Needs an agreement |
| **Spotify Web API** | Not integrated | ❌ (full playback only through the Spotify SDK for Premium users) | Mostly removed | Developer Terms restrict commercial use, and playback must go through Spotify's own SDK/app | OAuth | Per app | No caching of content. Strict metadata caching rules | Spotify attribution rules | ⛔ Not suitable for this business model without a partnership |
| **SoundCloud** | Not integrated | Varies | – | Requires an approved app and compliance with API terms. New registrations are often closed | OAuth | Per app | No downloading | SoundCloud attribution | ⛔ Not pursued |
| **YouTube / YouTube Music** | **Never** | – | – | Terms forbid separating audio from video and background audio playback | – | – | – | – | ❌ Prohibited |
| **Musixmatch / LyricFind** (lyrics) | Not integrated | – | – | Lyrics need a **paid licence** (publishers' rights) | API key | Per plan | Per licence | Required | ⛔ Paid licence needed. The lyrics feature was removed |

Sources I checked while writing this:
[Audius API docs](https://docs.audius.org/api),
[Audius terms update (Jul 2025)](https://blog.audius.co/posts/audius-terms-of-service-update),
[Audius Open Music Licence](https://audius.org/open-music-license.pdf),
[Jamendo API terms](https://devportal.jamendo.com/api_terms_of_use),
[Deezer developer FAQ](https://support.deezer.com/hc/en-gb/articles/360011538897-Deezer-FAQs-For-Developers),
[Deezer guidelines](https://developers.deezer.com/guidelines),
[iTunes Search API](https://performance-partners.apple.com/search-api).

## How each integration works

All providers implement `lib/sources/music_source.dart`:

```dart
abstract class MusicSource {
  SourceInfo get info;                       // id, name, full/preview, commercial status, attribution
  Future<List<Song>> searchTracks(String q, {int limit});
  Future<List<Song>> featuredTracks({int limit});      // optional
  Future<List<Song>> artistTracks(String artistId);    // optional
  Future<List<Song>> albumTracks(String albumId);      // optional
  Future<Uri?> resolveStream(Song song);               // lazy stream lookup
}
```

Each returned `Song` carries a `Playability` (`full`, `preview`, `none`,
`local`) that the **integration** decides from the provider's terms. The UI
never upgrades it.

### Audius (`lib/sources/audius_source.dart`)
- Host `api.audius.co` (override with `AUDIUS_API_HOST`), plus `app_name=<AUDIUS_APP_NAME>` on every call.
- `GET /v1/tracks/search?query=`, `/v1/tracks/trending`, `/v1/users/{id}/tracks`, `/v1/playlists/{id}/tracks`.
- Stream: `GET /v1/tracks/{id}/stream?app_name=…` (redirects to a content node).
- Tracks are dropped when `is_streamable == false`, `stream_conditions` is set (pay or follow gated), or `access.stream == false`.

### Internet Archive (`lib/sources/internet_archive_source.dart`)
- Search: `advancedsearch.php`, filtered by Lucene on `licenseurl` (public domain / CC BY / CC BY-SA). The app checks the licence again (`isCommercialLicence`) and rejects anything `-nc`.
- Stream: resolved lazily via `GET /metadata/{identifier}`, which picks the first MP3 (or OGG).

### iTunes (`lib/sources/itunes_source.dart`)
- `GET /search?entity=song&media=music&country=…` and `GET /lookup?id=…&entity=song` (album / artist pages).
- Returns `Playability.none` unless `ITUNES_PREVIEWS=true`. It provides the catalogue "truth" (title, album, duration, artwork) used for matching and display.

### Jamendo (`lib/sources/jamendo_source.dart`)
- `GET /v3.0/tracks/?client_id&search&audioformat=mp32&include=licenses`.
- Registered only when the build is configured as having a commercial agreement.

## Adding or removing a provider

1. Implement `MusicSource` in `lib/sources/your_source.dart`. Set
   `Playability` honestly and add a parser test in `test/sources/`.
2. Add it to `availableSourcesProvider` in `lib/providers/source_providers.dart`,
   behind an `AppConfig` flag if it needs an agreement.
3. Add a row to the matrix above.

To remove one, delete it from `availableSourcesProvider`. Nothing else depends
on a specific provider.

## What the user experiences when no authorised source exists

The track shows a **"Not streamable"** badge. Tapping it explains why and offers
"Open in Apple Music" (or the provider's page). The app never substitutes a
different recording: the matcher rejects covers, karaoke, live versions and
other artists (`test/search/matching_test.dart`).

## Honest expectation

Free, commercially usable APIs do **not** give full-length access to
mainstream major-label catalogues. With the providers above, users get:

- **Independent and artist-published music** (Audius) at full length.
- **Public-domain and CC-licensed recordings** (Internet Archive) at full length.
- **Mainstream songs**: identified correctly, with album and artwork, plus a link to
  listen on Apple Music (or a promotional preview if you enable it).

Full streaming of mainstream catalogues requires direct licences (labels,
publishers, PROs) or a B2B music service with commercial terms (for example
Feed.fm or 7digital). Both are paid agreements and are outside this
codebase's assumptions.
