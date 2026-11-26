# GitHub music API audit (OpenSpot, Saavn, DAB, Gonic and others)

This audit is research only. No Aurora Music code was changed. It was carried
out on 2026-11-26.

**Method**
- The repositories were cloned and their **source code** was read; READMEs were
  not taken at face value. Commits inspected:
  - `BlackHatDevX/openspot-music-app` at `640af82` (full history, 138 commits)
  - `sentriz/gonic` at `5e5338c`
  - `sixnine-dotdev/dab-api-docs`
  - `KRTirtho/dab_music_api`
  - `sumitkolhe/jiosaavn-api`
  - `V1ck3s/octo-fiesta`
- Other repositories were classified from GitHub search metadata and their
  descriptions. They are marked as such.
- Live checks were run from the development sandbox. Each check was limited to
  three things:
  - whether the service answers;
  - search metadata only;
  - whether a stream field is present.

**Not done, on purpose**
- No audio was downloaded or played from JioSaavn, DAB or YouTube/Invidious.
- No protected media URL was decrypted.
- No bot challenge was bypassed.
- No credential (keys, tokens) is reproduced in this document.

**Evidence labels**
- **Confirmed**: seen in source code or in a live response.
- **Inferred**: a strong indication, not proof.
- **Unknown**: not established.

---

## Summary for decision-makers

- **OpenSpot is not an API provider.** It is a React Native / Tauri app.
  - It streams and downloads from **JioSaavn's private web API**. Stream URLs
    come from decrypting JioSaavn's `encrypted_media_url` with a key hard-coded
    in the app.
  - It also uses **public Invidious instances**, which extract YouTube audio
    streams.
  - It originally used **DAB** (`dab.yeet.su`), a third-party service that
    re-serves another catalogue (inferred: Qobuz).
  - None of these is an authorised distribution channel for a third-party
    commercial app.
- **"Savan" = JioSaavn's undocumented internal API** (`/api.php?__call=…`). It
  is not an official public API. It holds a lot of Bangla music, but using its
  audio in Aurora would mean circumventing a protection measure and streaming
  without a licence.
- **DAB Music API** is a community service.
  - It requires an account and is behind a Cloudflare bot challenge.
  - Its own OpenAPI document demands that any software using it be
    **AGPLv3-compatible**.
  - It has no licence from rights holders that we could find.
  - Not usable for Aurora.
- **Gonic** is a legitimate **self-hosted Subsonic server for the user's own
  files**, not a catalogue. Aurora could add a **Subsonic/OpenSubsonic client**
  (talking to Gonic, Navidrome, Airsonic and others over HTTP) without copying
  GPL code. This is the one new integration recommended.
- None of the 25+ "free music API" repositories found gives legally authorised
  full-track streaming of mainstream or Bangla catalogues for a commercial
  third-party app.

---

## PART 1 – OpenSpot (`BlackHatDevX/openspot-music-app`, MIT)

### Structure

| Path | What it is |
|---|---|
| `openspot-mobile/` | Expo / React Native app (Android, iOS) |
| `openspot-desktop/` | Same codebase plus a Tauri 2 shell (`src-tauri/`) |
| `openspot-*/lib/music-api.ts` | Provider switch: `saavn` (default) or `ytmusic`, stored in AsyncStorage (`openspot_provider_v1`) |
| `openspot-*/lib/api.ts` | JioSaavn client ("Saavn") |
| `openspot-*/lib/ytmusic-api.ts` | YouTube via Invidious instances |
| `openspot-*/lib/spotify-import.ts` | Spotify playlist import through a third-party "transfer" site |
| `openspot-desktop/app/api/saavn+api.ts` | Expo server route that proxies JioSaavn calls |
| `openspot-desktop/src-tauri/src/lib.rs` | Rust `proxy_http` command (reqwest) and file writes for downloads |
| `openspot-*/components/DownloadButton.tsx` | Offline downloads (`expo-file-system` `createDownloadResumable`) |

### Every external service found in the source (Confirmed)

| Service | Endpoint pattern | Source files | Purpose |
|---|---|---|---|
| **JioSaavn private web API** | `${EXPO_PUBLIC_API_BASE_URL}?__call=<endpoint>&_format=json&_marker=0&api_version=4&ctx=web6dot0&…`. The base URL is hidden in env; `.env.template` says *"check exact API on Telegram channel"*. `sumitkolhe/jiosaavn-api` uses `https://www.jiosaavn.com/api.php` for the same calls (`src/common/helpers/fetch.helper.ts:18`). | `openspot-mobile/lib/api.ts:5-70`, `openspot-desktop/lib/api.ts`, `openspot-desktop/app/api/saavn+api.ts` | Search, song details, albums, artists, playlists, trending |
| JioSaavn `__call` endpoints used | `search.getResults`, `search.getArtistResults`, `search.getPlaylistResults`, `search.getAlbumResults`, `song.getDetails` (`pids`), `content.getAlbumDetails` (`albumid`), `artist.getArtistMoreSong`, `playlist.getDetails` (`listid`), `webapi.get`, `content.getTrending` | `openspot-mobile/lib/api.ts:195-667` | — |
| **Third-party CORS proxy** | `POST https://nextjs-proxy-gamma.vercel.app/api/proxy` with `{url, method, headers}`. Every JioSaavn call except `song.getDetails` goes through it, with a random browser User-Agent. | `openspot-mobile/lib/api.ts:35-70` | Hides the client and avoids CORS/geo limits. All search traffic passes through an unknown operator. |
| **JioSaavn media decryption** | `createDownloadLinks(encrypted_media_url)` decrypts with `CryptoJS.DES` (ECB) using a **hard-coded key**, then swaps `_96` for `_12/_48/_96/_160/_320` to choose a bitrate. Stream and download both use the 320 kbps URL. | `openspot-mobile/lib/api.ts:73-100`, `:404-428` | Turns JioSaavn's protected media field into a direct CDN audio URL |
| **Invidious (YouTube)** | Search: `{instance}/api/v1/search?q=…&type=video&fields=videoId,title,author,lengthSeconds,videoThumbnails`. Stream: `{instance}/api/v1/videos/{id}?fields=adaptiveFormats`, then the best audio `itag`; when proxied, `{instance}/latest_version?id={id}&itag={itag}&local=true`. Downloads reuse the stream URL. | `openspot-mobile/lib/ytmusic-api.ts:22-31, 142-300` | Audio-only extraction from YouTube videos |
| Invidious instance lists | `EXPO_PUBLIC_YT_API_INSTANCES` and `EXPO_PUBLIC_YT_API_DISCOVERY` (format matches the Invidious instances list), plus `https://raw.githubusercontent.com/BlackHatDevX/openspot-config/refs/heads/main/ytmusicextraapi.json` (live: lists public Invidious hosts such as `invidious.f5.si`, `inv.nadeko.net`) | `lib/ytmusic-api.ts:22-31` | Rotating instances |
| **Spotify playlist import** | `https://api.${EXPO_PUBLIC_SPOTIFY_FETCHER_DOMAIN}.com/v2/Transfer/LoadLibrary` and `/LoadPlaylistTracks`, with spoofed `Origin`, `Referer` and `x-original-URL` of that site. The bearer token comes from `openspot-config/…/spotify-playlist-token.json` (not fetched by this audit). | `openspot-mobile/lib/spotify-import.ts:5-100` | Uses a third-party playlist-transfer website's private API; **not** the Spotify Web API |
| Remote config / kill switch | `openspot-config/…/apistatus.json` (live: `{ytmusic:{disabled:false}, saavn:{disabled:false}}`), `update.json`, `update-desktop.json` | `hooks/useApiStatus.ts:3`, `app/(tabs)/_layout.tsx`, `settings.tsx` | Turns providers on and off remotely |
| Charts | `https://kworb.net/spotify/` (HTML scraping of Spotify chart mirrors) | `app/(tabs)/index.tsx:24,118,149` | "Trending" lists |
| Geolocation | `https://ipinfo.io/json` | `app/(tabs)/index.tsx:162,197` | Picks the country chart |
| Connectivity | `https://clients3.google.com/generate_204` | `hooks/useConnectivity.ts` | — |
| Artwork | `https://i.ytimg.com/vi/{id}/hqdefault.jpg`, JioSaavn image CDN (`150x150` → `500x500` rewrite) | `lib/ytmusic-api.ts:187`, `lib/api.ts:103-113` | — |

**Not present in the current source:** Spotify Web API (`api.spotify.com`),
YouTube Data API, DAB and Qobuz. A search across all files found no `dab` or
`qobuz` references.

### Provider history (git, Confirmed)

| Date | Commit | Change |
|---|---|---|
| 2025-07-14 | `f5991ac` | First version. `lib/api.ts`: `API_BASE_URL = 'https://dab.yeet.su/api'` with `SEARCH: '/search'` and `STREAM: '/stream'`. `lib/music-api.ts` called `GET /search?q&offset&type` and `GET /stream?trackId=`. The track model (`types/music.ts`) carries `maximumBitDepth`, `maximumSamplingRate`, `isHiRes`, `upc`, `label`, `genreSlug`, `releaseDateStream`, `purchasable` and `isrc`. |
| 2025-07-15 | `f10b014` | The DAB URL is moved into the hidden env variable `EXPO_PUBLIC_API_BASE_URL`. |
| 2025-07-15/16 | `aa6d89e`, `4c2b0b2` | README: *"streaming is powered by dab.yeet.su"*. The About screen shows the DAB icon. |
| 2026-04-27 | `0e0dc8d` (v2.0.5-init) | Rewritten for **JioSaavn** (`saavn_search_*` cache keys). The same env variable now points at JioSaavn. |
| 2026-04-28 → 06 | v3.x | Invidious "YouTube API" added; desktop moved to Tauri; Spotify import. |

**Conclusion (Confirmed):** OpenSpot does not hold any music licence. It
re-uses other services' private endpoints, hides their addresses in env
variables and remote config, and offers **downloads** of the resulting audio.

---

## PART 2 – "Savan" (JioSaavn) API

| # | Question | Answer |
|---|---|---|
| 1 | What is it? | **JioSaavn's internal web API**: the endpoints the jiosaavn.com website calls (`/api.php?__call=…`). "Saavn"/"Savan" in OpenSpot is a nickname, not a separate service. *(Confirmed: identical `__call` names and parameters in OpenSpot and in `sumitkolhe/jiosaavn-api`, which targets `https://www.jiosaavn.com/api.php`.)* |
| 2 | Official or community? | **Neither is a public API.** The endpoint belongs to JioSaavn but is undocumented and not offered to developers. The GitHub "JioSaavn APIs" are **community wrappers** that call it; e.g. `sumitkolhe/jiosaavn-api` calls itself "An Unofficial API for downloading … songs". |
| 3 | Public documentation? | No official documentation. Community wrappers document their own REST layer only. |
| 4 | Search endpoints | `search.getResults` (songs; `q`, `p`, `n`), `search.getAlbumResults`, `search.getArtistResults`, `search.getPlaylistResults`. **Live: answered.** |
| 5 | Song-detail endpoints | `song.getDetails` (`pids`), plus `webapi.get` (token/link lookup) and `content.getAlbumDetails`, `playlist.getDetails`, `artist.getArtistMoreSong`. |
| 6 | Direct audio URLs? | **Not in clear form.** Responses contain `more_info.encrypted_media_url` (live: present on every result). Clients turn it into a CDN URL by DES-decrypting it with a key embedded in JioSaavn's web player and copied into OpenSpot. That is circumvention of a technical protection measure. *Not done here.* |
| 7 | Full tracks or previews? | The decrypted URLs are **full tracks** at 96/160/320 kbps. *(Confirmed in code; `320kbps: true` flags were seen live. Audio itself not fetched.)* |
| 8 | Bangla? | **Yes, extensive.** Live: "Bondho Janala" by Shironamhin, 242 s, label "Shironamhin"; Artcell's "Aniket Prantor" album; Warfaze "Obak Bhalobasha (Coke Studio Bangla)". |
| 9 | Bengali Unicode? | **Yes.** Live: the query `শিরোনামহীন` returned 57 results, all by Shironamhin. |
| 10 | English and Hindi? | Hindi yes (it is JioSaavn's core catalogue). English: **live searches for Ed Sheeran "Perfect", Adele "Hello", Coldplay "Yellow" and Linkin Park "Numb" returned no recording by those artists**, only karaoke, covers and sped-up versions. A "Bohemian Rhapsody – Queen" hit was 218 s (the original is about 355 s), on label "Gold World Music", tagged "haryanvi", so not the original. *Inferred:* JioSaavn's catalogue is licensed per territory, and results depend on the requester's country (sandbox egress location unknown). |
| 11 | Authentication? | None for search. OpenSpot uses random browser User-Agents and a third-party proxy. |
| 12 | Rate limits? | Not documented. *Unknown*; community wrappers report blocking, which is why proxies are used. |
| 13 | Another service behind it? | JioSaavn's own backend and CDN. Community "Saavn APIs" sit in front of it, and OpenSpot adds a Vercel proxy. |
| 14 | Stable URLs? | No. The endpoint is internal and can change without notice. Media URLs are CDN links derived by decryption; their lifetime is *unknown*. |
| 15 | Licensing | JioSaavn's catalogue is licensed to JioSaavn for its own apps, mainly in India. No licence is offered to third-party apps. Using the internal API, decrypting media and downloading is **not authorised** and likely breaches JioSaavn's terms and copyright/anti-circumvention law. |

**Classification: Not recommended** (for streaming or downloading). Even as
metadata only, it is an undocumented private endpoint with no permission, so
it is not recommended either. Contact JioSaavn for a partnership if its
catalogue is needed.

---

## PART 3 – DAB Music API

| Item | Finding |
|---|---|
| Service | "DAB Music Player". Old host `dab.yeet.su` (OpenSpot 2025); current host **`dabmusic.xyz`** according to its OpenAPI document. *(Confirmed: `sixnine-dotdev/dab-api-docs/openapi.yaml`)* |
| Official website | `https://dabmusic.xyz`, named as the contact in `openapi.yaml`. |
| Source repository | No server source found. Community clients exist: `sixnine-dotdev/OpenDAB` (web player), `KRTirtho/dab_music_api` (Dart client generated from the OpenAPI spec), `joei4u/Dab-Android-Beta-V2` (Flutter app), and **downloaders** `PrathxmOp/dab-downloader` and `Ali5onbol/dab-downloader` ("download high-quality FLAC"). |
| API documentation | Community Swagger UI: `sixnine-dotdev/dab-api-docs` (OpenAPI 3.1, v1.0.1). |
| Search | `GET /search?q&type&limit` (tracks, albums, artists). Also `/album`, `/album/{id}`, `/discography?artistId`. |
| Streaming | `GET /stream` (`trackId`, `quality`). Downloads: `GET /download` (`albumId`, `quality`). OpenSpot 2025 used `GET /stream?trackId=` and `${API}/stream/${id}`. |
| Authentication | **Required:** a JWT in an HTTP-only `session` cookie (`/auth/login`, `/auth/register`). |
| Catalogue | *Inferred, not confirmed: Qobuz.* Evidence: OpenSpot's DAB-era track model uses Qobuz's field set (`maximumBitDepth`, `maximumSamplingRate`, `isHiRes`, `upc`, `genreSlug`, `releaseDateStream`, `purchasable`), and DAB downloaders advertise hi-res FLAC. |
| Bangla coverage | *Unknown.* Not testable; see operational status. |
| Full tracks | Advertised (FLAC). Not verified. |
| Restrictions / licence | `openapi.yaml` says: *"By using this API or building on it, you agree that any software or service that incorporates it must also be made available under an open-source license compatible with AGPLv3."* No evidence of any licence from labels or Qobuz. |
| Operational? | **Live (2026-11-26):** `dabmusic.xyz` (site and `/api/search`) returns **HTTP 403 with a Cloudflare "Just a moment…" bot challenge** to automated clients, and was not bypassed. `dab.yeet.su` accepted a TCP/TLS tunnel but returned **no HTTP response within 20 s**. So it is not usable from an app without passing a browser challenge. |

**Classification: Not recommended.** It is an unlicensed re-distribution of a
commercial catalogue, needs an account, has a bot challenge, and its AGPLv3
condition is incompatible with selling Aurora as a closed app.

---

## PART 4 – Gonic (`sentriz/gonic`, GPL-3.0)

| Topic | How it works (Confirmed from source) |
|---|---|
| What it is | A **self-hosted music server** that implements the **Subsonic / OpenSubsonic API** over your own audio files. `cmd/gonic/gonic.go:59-74`: `-music-path` (required, can repeat), `-listen-addr` (default `0.0.0.0:4747`), `-db-path` (SQLite). **It has no public catalogue.** |
| API routes | `server/ctrlsubsonic/ctrl.go:111-186`: `/ping`, `/getLicense`, `/getMusicFolders`, `/search2`, `/search3`, `/getArtists`, `/getArtist`, `/getAlbum`, `/getAlbumList2`, `/getSong`, `/getRandomSongs`, `/stream`, `/download`, `/getCoverArt`, `/getLyrics`, `/getPlaylists`, `/getPlaylist`, `/createPlaylist`, `/updatePlaylist`, `/deletePlaylist`, `/star`, `/unstar`, `/setRating`, `/scrobble`, `/savePlayQueue`, `/getPlayQueue`, `/getInternetRadioStations`, podcasts, bookmarks, jukebox, `getOpenSubsonicExtensions`. Usually served as `/rest/<name>(.view)`. |
| Authentication | `ctrl.go:222-300`. Every request needs `u` (user) and `c` (client name). Then **either** `t` + `s` (token = `md5(password + salt)`, the recommended Subsonic method) **or** `p` (plain or `enc:`-hex password). The OpenSubsonic `apiKey` method is not implemented (no match in the source). Use HTTPS, because the token scheme relies on the server storing the password. |
| Indexing | `scanner/scanner.go` walks the music paths and reads tags with `go.senan.xyz/taglib` (and `tags/ffprobe`) into SQLite. It stores a **Unidecode-transliterated copy** of names (`*_u_dec`, `scanner.go:981,1102`, `github.com/rainycape/unidecode`). |
| Search | `handlers_by_tags.go:216-240` (`search3`): `name LIKE %q% OR name_u_dec LIKE %q%`, with words joined by `%` (`buildFuzzy`, `handlers_common.go:850`). Bengali-script tags also match ASCII queries through the Unidecode column (*inferred from code; not tested with Bengali files*). |
| Streaming | `handlers_raw.go` `ServeStream`: serves the raw file (HTTP range-capable) when `format=raw`, on `/download`, or when `maxBitRate` ≥ the file bitrate. Otherwise it transcodes with ffmpeg profiles (`transcode/`). |
| Playlists | Server-side playlists per user (`handlers_playlist.go`), plus the play queue, starring and ratings. |
| Personal collection | **Yes, that is its purpose.** The user runs it on a PC, NAS or VPS, points it at files they own, and any Subsonic client can stream from it. |
| Can Aurora connect? | **Yes, as a client over HTTP**: `GET {server}/rest/search3?query=…&u=…&t=…&s=…&c=aurora&v=1.16.1&f=json`, and `…/rest/stream?id=…` for playback through just_audio. The same client would work with **Navidrome, Airsonic-Advanced, LMS, Ampache (Subsonic mode)** and others. |
| GPL-3.0 implications | Aurora only **talks to** Gonic over its network API, so it is not a derivative work and GPL does not apply to Aurora. **Copying or translating Gonic's Go code** into Aurora would make that part GPL-3.0, which is incompatible with a closed commercial app. Implement the client independently from the public Subsonic/OpenSubsonic API specification. Running Gonic is the user's business. |

**Classification: Personal library only. Recommended** as an optional "Connect
your music server" feature: the user streams files they already own.

---

## PART 5 – GitHub repositories reviewed

The type labels used below mean:
- **API provider**: runs a service with its own catalogue rights.
- **Wrapper**: calls another company's API (often a private one).
- **Self-hosted**: serves the user's own files.
- **Player**: a complete client app.
- **Metadata**: no audio.
- **Downloader**, **Scraper**, **Unofficial streaming**: as named.

Stars and recent activity are shown for context only. They do not prove
reliability or legality.

| # | Repository | Licence | Type | Actual service behind it | Basis |
|---|---|---|---|---|---|
| 1 | `BlackHatDevX/openspot-music-app` ★3.1k | MIT | Player + downloader (unofficial streaming) | JioSaavn private API (decrypted), Invidious/YouTube, earlier DAB | Source |
| 2 | `sentriz/gonic` ★2.7k | GPL-3.0 | **Self-hosted** Subsonic server | User's own files | Source |
| 3 | `sixnine-dotdev/dab-api-docs` | none | API documentation (community) | DAB Music (`dabmusic.xyz`) | Source |
| 4 | `KRTirtho/dab_music_api` | none | Wrapper (Dart, generated from OpenAPI) | DAB | Source |
| 5 | `sixnine-dotdev/OpenDAB` | MIT | Player | DAB | Description |
| 6 | `joei4u/Dab-Android-Beta-V2` ★360 | NOASSERTION | Player (Flutter) | DAB | Description |
| 7 | `PrathxmOp/dab-downloader` ★223 | none | **Downloader** (FLAC) | DAB | Description |
| 8 | `sumitkolhe/jiosaavn-api` ★504 | MIT | Wrapper / unofficial streaming ("for downloading … songs") | JioSaavn `www.jiosaavn.com/api.php` | Source |
| 9 | `cyberboysumanjay/JioSaavnAPI` ★473 | MIT | Wrapper (Python) | JioSaavn internal API | Description |
| 10 | `anxkhn/jiosaavn-api` | GPL-3.0 | Wrapper ("fetch DRM-free songs") | JioSaavn | Description |
| 11 | `tuhinpal/JiosaavnAPI` (archived) | Apache-2.0 | Wrapper | JioSaavn | Description |
| 12 | `Itz-Anya/Saavn-Api`, `ODSkyler/jiosaavn-api`, `adityaprakashgupta/Jio-Saavn-API` | none / MIT / BSD-3 | Wrappers | JioSaavn | Description |
| 13 | `wiz64/saavn-web-ui`, `Harshshah6/SaavnMp3-Android` | MIT | Player + **downloader** | JioSaavn (via wrappers) | Description |
| 14 | `mohd-baquir-qureshi/music-api` | none | Wrapper ("stream 320 kbps from popular services") | Unofficial | Description |
| 15 | `V1ck3s/octo-fiesta` ★955 | GPL-3.0 | Subsonic proxy + **downloader** | Deezer (user's ARL token), Qobuz (`QobuzBundleService.cs` extracts the app id/secret from `play.qobuz.com`'s JS bundle), Tidal, Yandex, deprecated SquidWTF. It has stream **decryptors** (`DeezerDecryptedStream.cs`, `TidalStreamDecryptor.cs`). | Source |
| 16 | `sigma67/ytmusicapi` ★3.1k | MIT | Wrapper (metadata, uses the private YouTube Music InnerTube API) | YouTube Music | Description |
| 17 | `tombulled/innertube` | MIT | Wrapper (private YouTube API) | YouTube | Description |
| 18 | `nukeop/nuclear` ★19k | AGPL-3.0 | Player (finds streams, mostly on YouTube) | YouTube and others | Description |
| 19 | `gokadzev/Musify` ★4.5k | GPL-3.0 | Player (YouTube streaming) | YouTube | Description |
| 20 | `staniel359/muffon` ★2.3k | AGPL-3.0 | Player (multi-source) | Various | Description |
| 21 | `navidrome/navidrome` (not in the search above; well known) | GPL-3.0 | **Self-hosted** Subsonic/OpenSubsonic server | User's own files | Known project |
| 22 | `airsonic/airsonic` (archived), `epoupon/lms`, `IrosTheBeggar/mStream`, `blackcandy-org/blackcandy`, `ironsmile/euterpe` | GPL / MIT | **Self-hosted** servers | User's own files | Description |
| 23 | `supersonic-app/supersonic`, `BLeeEZ/amperfy`, `victoralvesf/aonsoku`, `tamland/airsonic-refix` | GPL / MIT / AGPL | Players (Subsonic clients) | User's server | Description |
| 24 | `music-assistant/server` ★3.4k | Apache-2.0 | Self-hosted library manager (connects to the user's own accounts and servers) | Various | Description |
| 25 | `shazamio/ShazamIO` ★1k | MIT | Wrapper (reverse-engineered Shazam), metadata | Shazam | Description |
| 26 | `EbbLabs/python-tidal`, `AmineSoukara/amazon-music` | LGPL-3.0 / MIT | Wrappers needing the user's subscription | Tidal / Amazon | Description |
| 27 | `SwapnilSoni1999/spotify-dl` ★1.7k | MIT | **Downloader** (Spotify metadata → YouTube audio) | YouTube | Description |
| 28 | `chayotic/Open-Source-Music-Streaming-Apps` | CC0 | Curated list | — | Description |

**Bangla-specific:** searches for "bangla music api" and "bengali music"
returned **no music API**, only IPTV playlists, small personal players and a
recommendation-system notebook.

---

## PART 6 – Real search tests (live, 2026-11-26)

These columns are not repeated in every row:
- **Audio URL / full audio**: JioSaavn rows have only an encrypted field and
  were not decrypted; Audius and Internet Archive rows were not probed for
  these songs.
- **Playback succeeded**: not attempted for any service, on purpose.

**Bangla (JioSaavn, `search.getResults`; Aurora's providers are from `test_live/` run 2)**

| Song | Search response | Exact title | Exact artist | Duration | Original? | Use authorised? | Aurora's providers |
|---|---|---|---|---|---|---|---|
| Shironamhin – Hashnahena | 0 results (also with `Hashnahena` alone) | — | — | — | — | — | Not in iTunes; no Audius/Archive original |
| Shironamhin – Bondho Janala | 6 results | ✔ "Bondho Janala" | ✔ Shironamhin (label "Shironamhin") | 242 s | Likely (artist's own label) | **No** | iTunes identifies it; no authorised stream |
| Arnob – She Je Boshe Ache | 1 result | ~ "Shey Je Boshe Ache" | ✘ Mashuq Haque, Rishi Panda | 287 s | **No** (other artists) | **No** | iTunes identifies Arnob's; no stream |
| Habib Wahid – Maya | 8 results | ✔ "Maya" | ✘ "Saanjh", label "Music Cover Group" | 233–356 s | **No** (covers) | **No** | iTunes: results; no stream |
| Warfaze – Obak Bhalobasha | 1 result | ~ "Obak Bhalobasha \| Coke Studio Bangla" | ✔ Warfaze | 408 s | **Different version** (Coke Studio live re-recording) | **No** | iTunes identifies the original; no stream |
| Artcell – Oniket Prantor | 5 results (album "Aniket Prantor", other tracks) | ✘ title track not in the top 5 | ✔ Artcell | — | — | **No** | iTunes identifies it; no stream |
| `শিরোনামহীন` (Unicode) | 57 results, all Shironamhin | — | ✔ | — | — | **No** | Audius finds Shironamhin uploads |

**English (JioSaavn; full 40-result list checked for each artist)**

| Song | Search response | Recording by the artist? | Notes | Use authorised? |
|---|---|---|---|---|
| Ed Sheeran – Perfect | 23 results | **None** | Marimba, karaoke and cover versions only | **No** |
| Adele – Hello | 4 | **None** | Karaoke only | **No** |
| Coldplay – Yellow | 3 | **None** | Karaoke and piano covers | **No** |
| Linkin Park – Numb | 9 | **None** | Sound-alikes and sped-up versions | **No** |
| Queen – Bohemian Rhapsody | 8 | One hit credited "Queen", **218 s**, label "Gold World Music", tagged "haryanvi" | Not the original (about 355 s) | **No** |

In Aurora's own pipeline (`test_live/`, run 2), all five English songs were
identified by the Apple catalogue and correctly shown as **"Original recording
unavailable"**. JioSaavn's results show why an exact-recording matcher is
essential: without one, a karaoke version would have played as "Perfect – Ed
Sheeran".

**Other services**

| Service | Result |
|---|---|
| DAB | `dabmusic.xyz` returned 403 (Cloudflare challenge); `dab.yeet.su` returned no HTTP response. **Could not be tested.** |
| Invidious (`inv.nadeko.net`, from OpenSpot's list) | **HTTP 502** on `/` and `/api/v1/stats`. Not tested further; YouTube audio extraction is prohibited by YouTube's terms either way. |
| Gonic | Not deployed. It only serves files the user provides, so there is nothing catalogue-wide to search. |

---

## PART 7 – Comparison and recommendations

| Repository/API | Actual service | Free? | API key | Bangla | English | Full audio | Licensing | Stability | Recommendation |
|---|---|---|---|---|---|---|---|---|---|
| OpenSpot | JioSaavn private API, Invidious, earlier DAB | Free app | No (hidden env URLs) | Via JioSaavn | Via YouTube | Yes (decrypted or extracted) | **Unauthorised** | Relies on a proxy and remote kill switch; providers changed twice in 10 months | **7. Not recommended** |
| "Savan" / JioSaavn internal API and its wrappers | JioSaavn | Free to call | No | **Yes, strong** | Limited by region | Yes, after **DES decryption** | **Unauthorised**; ToS and anti-circumvention issues | Undocumented; blocking causes proxy use | **7. Not recommended** (a partnership with JioSaavn would be **6. Requires licensing agreement**) |
| DAB Music API | Community service; inferred Qobuz catalogue | Free account | Session cookie (JWT) | Unknown | Unknown | Claimed FLAC | **Unauthorised**; AGPLv3 condition | Cloudflare-gated; old host dead | **7. Not recommended** |
| Invidious / YouTube extraction | YouTube | Free | No | Yes | Yes | Yes (extracted) | **Prohibited** by the YouTube API Services Terms | Public instances fail often (live 502) | **7. Not recommended**. Use **3. External player only** (YouTube Data API + official player, already in Aurora) |
| `ytmusicapi` / InnerTube | YouTube Music private API | Free | No | Yes | Yes | No (metadata) | Private API, not licensed | Breaks when Google changes it | **7. Not recommended** |
| octo-fiesta (Deezer/Qobuz/Tidal) | User's own subscriptions + stream decryption | Needs a paid subscription | User tokens | Varies | Yes | Yes (decrypted) | Breaks the providers' terms (decryption, secret extraction) | — | **7. Not recommended** |
| **Gonic / Navidrome / other Subsonic servers** | User's own files | Free (self-hosted) | User account | Whatever the user owns | Whatever the user owns | **Yes** | User's own content; GPL only if code is copied | Stable public Subsonic API | **4. Personal library only (recommended)** |
| Audius (already in Aurora) | Audius | Free | No (`app_name`) | Some artists | Indie | Yes | Public API for third-party apps | Good | **1. Recommended** |
| Internet Archive (already) | archive.org | Free | No | Little | PD/CC | Yes (per-item licence) | CC0/PD/BY/BY-SA only | Good | **1. Recommended** |
| Apple iTunes Search (already) | Apple | Free | No | Identifies | Identifies | No | Metadata + store links | Good (rate-limited) | **2. Metadata only** |
| MusicBrainz (already, off) | MetaBrainz | Free for non-commercial use | No | Partial | Yes | No | Commercial plan needed | Sometimes busy (live 503) | **2. Metadata only** (with plan) |
| YouTube Data API (already, off) | Google | Quota | Yes | Yes | Yes | No | Official player only | Good | **3. External player only** |
| Radio Browser (already) | Community directory | Free | No | Yes (stations) | Yes | Live radio | Per-station licences | Good | **1. Recommended** (radio feature) |
| JioSaavn / Shadhin / Gaana / Spotify partnerships | — | Paid / partner | Partner credentials | Yes | Yes | Yes, if licensed | Contract | — | **6. Requires licensing agreement** |

### What to consider integrating into Aurora Music

1. **Subsonic/OpenSubsonic client ("Connect your music server").** This is
   the only new integration worth building from this research.
   - Users connect Aurora to their own Gonic, Navidrome, Airsonic, LMS or
     Ampache server and stream music **they own**, including large Bangla
     collections.
   - Implement it from the public API specification (token auth
     `md5(password+salt)` over HTTPS, `search3`, `getAlbum`, `stream`,
     playlists). Do **not** copy GPL code.
   - Label these tracks "Your server" in a separate source kind, keep them out
     of the authorised-catalogue matching, and never upload server
     credentials.
2. **Keep** the current authorised providers: Audius, Internet Archive, iTunes
   metadata, Radio Browser, and the official external players.
3. **Do not integrate** OpenSpot's providers (JioSaavn internal API, DAB,
   Invidious) or any wrapper, downloader or decryptor listed above. They
   expose playable URLs, but that does not make playback authorised. Several
   require circumventing protection measures, and some (DAB) impose AGPLv3
   conditions.
4. **For Bangla catalogue coverage**, the legitimate route is a **licensing
   agreement**: JioSaavn, Shadhin, or Bangladeshi labels and distributors
   (e.g. G-Series, Laser Vision). Alternatively, approach artists to publish
   on Audius.

### Confirmed facts vs assumptions

**Confirmed**
- Every endpoint, file path, commit and licence quoted above.
- OpenSpot's JioSaavn media decryption.
- OpenSpot's use of a third-party proxy and Invidious.
- The DAB history in OpenSpot.
- DAB's AGPLv3 clause and cookie authentication.
- Gonic's routes, authentication, search and Unidecode indexing.
- The live JioSaavn search results.
- DAB, Invidious and MusicBrainz availability results on the test date.

**Inferred**
- DAB's catalogue is Qobuz.
- JioSaavn's English results depend on the requester's region.
- Gonic's Unidecode column makes Bengali-tagged files searchable in Latin
  script.

**Unknown**
- JioSaavn's rate limits and media-URL lifetime.
- DAB's current Bangla coverage and real availability.
- Who operates `nextjs-proxy-gamma.vercel.app` and the Spotify "transfer"
  site.
