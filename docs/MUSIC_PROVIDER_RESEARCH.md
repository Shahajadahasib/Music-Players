# Music provider research

Research behind which providers Aurora Music uses, and how. It was last
reviewed in November 2026. Provider terms change, so re-check each one
before every release.

**How to read the evidence:**
- **Live-verified** means real requests were made from the development
  sandbox (see `test_live/`).
- **Docs** means the information comes from the provider's published
  documentation or terms only.
- Nothing here is legal advice. Before you sell the app, have someone
  qualified review the terms of each provider you enable.

The app must never:
- claim it can play every song;
- extract audio from video platforms;
- bypass DRM, sign-in, adverts or regional limits;
- call private or reverse-engineered endpoints;
- pass an external player's URL to the in-app audio player.

## Classifications

| Classification | Meaning in the app |
|---|---|
| **Approved for implementation** | Integrated and on by default |
| **Approved for metadata only** | Identifies songs (title, artist, album, ISRC, artwork). It never plays audio. |
| **Approved for preview only** | Short clips only, labelled "Preview" |
| **External-player only** | A link opens the provider's official player or app |
| **Experimental** | Not integrated; an adapter may be prepared, and it stays disabled |
| **Requires commercial agreement** | Integrated behind a build flag that stays off until you hold the agreement |
| **Not suitable** | Terms or technical facts rule it out |
| **Unavailable** | No public API exists, or it has been discontinued |

## Summary

| Provider | Kind in app | Classification | Flag / key | Status in code |
|---|---|---|---|---|
| Audius | full track | **Approved for implementation** | none (`AUDIUS_APP_NAME`) | on |
| Internet Archive | full track | **Approved for implementation** (CC0 / PD / CC BY / BY-SA items only) | `INTERNET_ARCHIVE` | on |
| Apple iTunes Search | metadata (+ preview) | **Approved for metadata only**; previews only to promote store content | `ITUNES_METADATA`, `ITUNES_PREVIEWS` | metadata on, previews off |
| Jamendo | full track | **Requires commercial agreement** | `JAMENDO_CLIENT_ID` + `JAMENDO_COMMERCIAL_AGREEMENT` | off |
| Free To Use | full track | **Requires commercial agreement** (paid Commercial licence) | `FREETOUSE_COMMERCIAL_LICENSE` | off |
| MusicBrainz | metadata | **Approved for metadata only**, but commercial use **requires a MetaBrainz plan** | `MUSICBRAINZ_ENABLED`, `MUSICBRAINZ_CONTACT` | off |
| YouTube Data API | external player | **External-player only** | `YOUTUBE_API_KEY` | off until a key is set |
| Radio Browser | radio | **Approved for implementation** (separate Radio screen) | `RADIO` | on |
| Spotify Web API | metadata / external | **Not suitable** today (quota limits; see below) | — | not integrated |
| Deezer API | metadata + 30 s preview | **Approved for preview only** in principle, but needs written confirmation | — | not integrated |
| Last.fm | metadata | **Requires commercial agreement** | (`LASTFM_API_KEY`) | not integrated |
| ccMixter | full track | **Not suitable** (content endpoints refused requests) | — | not integrated |
| Free Music Archive | full track | **Unavailable** (API discontinued) | — | not integrated |
| JioSaavn | full track / metadata | **Experimental**: no official public API; community wrappers only | — | not integrated |
| Shadhin Music | — | **Unavailable**: no public API; partner access only | — | not integrated |
| Gaana | — | **Unavailable**: no official public API | — | not integrated |
| SoundCloud | full track | **Requires commercial agreement** / app approval | — | not integrated |
| Audiomack | full track | **Requires commercial agreement** (approved apps only) | — | not integrated |
| Bandcamp | — | **Unavailable** for players (API is for labels and fulfilment partners) | — | not integrated |
| Openverse | metadata (CC audio index) | **Not suitable** as a separate source (its music duplicates Jamendo) | — | not integrated |
| Freesound | sound clips | **Not suitable** (sound effects; API commercial use needs an agreement) | (`FREESOUND_TOKEN`) | not integrated |
| Pixabay Music / Mixkit | — | **Unavailable** (no music API found) | — | not integrated |
| Musopen | — | **Unavailable** (no public API found) | — | not integrated |
| Openwhyd | external (YouTube/SoundCloud links) | **Not suitable** (it re-links third-party players) | — | not integrated |

## The 15 questions, per provider

The questions are:
1. Official website
2. API documentation
3. Is a key required?
4. Is there a free tier?
5. Can it search full songs?
6. Does it return metadata?
7. Does it provide previews?
8. Does it provide full-track playback?
9. Does it use an official external player?
10. Is use inside a third-party player permitted?
11. What are the commercial restrictions?
12. Does it have Bangla music?
13. Does it have English music?
14. Is it actively maintained?
15. Is it fit for production?

### Audius: Approved for implementation
1. https://audius.co
2. https://docs.audius.org
3. No key is needed for read endpoints. An `app_name` parameter is requested.
4. Yes.
5. Yes.
6. Yes, including licence and ISRC when the uploader sets them.
7. No.
8. Yes. Streams are served by Audius nodes; gated or non-streamable tracks are skipped.
9. No.
10. Yes. The API exists for third-party apps.
11. Uploaders hold the rights. Any user can upload, so an upload is **not** assumed to be an authorised commercial release. The matcher accepts a stream as "the original" only when the artist matches and no cover or re-upload markers are present.
12. Some (live: Shironamhin, Warfaze, Artcell, Arnob, Habib Wahid, Tahsan and others returned results).
13. Mostly independent artists. Major-label hits are generally absent (live: none of the English dataset songs had the original).
14. Yes.
15. Yes, with the matching and verification safeguards. **Live-verified.**

### Internet Archive: Approved for implementation (licence-filtered)
1. https://archive.org
2. https://archive.org/developers/
3. No.
4. Yes.
5. Yes, via advanced search.
6. Yes.
7. No.
8. Yes, but only items whose `licenseurl` is CC0, Public Domain, CC BY or CC BY-SA. NC and ND items are never requested.
9. No.
10. Yes, for items under those licences.
11. The licence is per item and supplied by the uploader. It is shown as "Licence not verified" when missing.
12. Little, mostly old recordings.
13. Old classics and public-domain recordings.
14. Yes.
15. Yes. **Live-verified.**

### Apple iTunes Search API: Approved for metadata only
1. https://www.apple.com/itunes/
2. Apple "iTunes Search API" documentation
3. No.
4. Yes. It is rate-limited (about 20 requests per minute); the app has its own limiter.
5. It searches the catalogue.
6. Yes. It is the main source for identifying the requested recording.
7. Yes, 30-second clips. Apple only permits them to promote store content, so they are off by default.
8. No.
9. "Open in Apple Music" links.
10. Metadata with a link back to the store.
11. Previews may only be used to promote sales.
12. Partial (Bangladeshi and West Bengal releases on Apple Music).
13. Yes, broad.
14. Yes.
15. Yes, as metadata. **Live-verified** (including rate limiting).

### Jamendo: Requires commercial agreement
1. https://www.jamendo.com
2. https://developer.jamendo.com/v3.0
3. Yes, a client id.
4. Yes, for **non-commercial** use only.
5. Yes.
6. Yes.
7. No.
8. Yes.
9. No.
10. Non-commercial apps only, unless you sign Jamendo's commercial licence.
11. Even with the agreement, tracks under NC licences are excluded per track (`allowsCommercialStreaming`).
12. Little.
13. Independent artists.
14. Yes.
15. Only with the agreement. Docs only, because no client id was available.

### Free To Use: Requires commercial agreement
1. https://freetouse.com
2. API at `api.freetouse.com/v3`, documented on the site.
3. No key for search.
4. Free use requires attribution and **excludes commercial digital products**.
5. Yes.
6. Yes.
7. No.
8. Yes (MP3).
9. No.
10. Only under a paid Commercial plan, for an app sold commercially.
11. Premium tracks are never played. The flag stays off until a licence is held.
12. No (background and royalty-free music).
13. Instrumental and background music.
14. Yes.
15. Only with the licence. **Live-verified** (search returns results).

### ccMixter: Not suitable
1. http://ccmixter.org
2. Query API (`/api/query`)
3. No.
4. —
5. —
6. —
7. —
8. Content requests returned **403** from the sandbox.
9. —
10. —
11. Licences are mostly CC BY-NC.
12. —
13. Remix community only.
14. Low activity.
15. No. **Live-tested** (blocked).

### Free Music Archive: Unavailable
The public API has been discontinued, and the site no longer issues API keys. Integrating FMA would mean scraping, so it was not done.

### JioSaavn: Experimental (not integrated)
- There is no official public developer API or developer portal. JioSaavn publishes an API *policy* page, but there is no programme to sign up for.
- The GitHub "JioSaavn API" projects call private endpoints. The audio URLs they return come with no licence for third-party apps.
- Per the brief: it is not claimed as official, not relied on, and no unknown proxies are used.
- It has strong Bangla, Hindi and English catalogues, but none of that is usable without a partnership.
- If one is signed, a `MusicSource` adapter with `experimental: true` can be added behind its own flag.

### MusicBrainz: Approved for metadata only (commercial plan required)
1. https://musicbrainz.org
2. https://musicbrainz.org/doc/MusicBrainz_API
3. No key. A descriptive User-Agent with a contact address is required (`MUSICBRAINZ_CONTACT`).
4. Free for non-commercial use. Commercial use needs a MetaBrainz supporter plan.
5. It searches recordings.
6. Yes: ISRCs, lengths, releases and artist credits.
7. No.
8. No.
9. No.
10. Metadata only.
11. Rate limit of 1 request per second. Commercial use needs a plan.
12. Partial (community-edited; some Bangladeshi bands).
13. Yes.
14. Yes.
15. Yes, as an off-by-default metadata source.

Evidence: **Live-verified** in the final test run (25 results for "Shironamhin"). An earlier attempt from the sandbox had its connection reset.

### YouTube Data API: External-player only
1. https://www.youtube.com
2. https://developers.google.com/youtube/v3
3. Yes, an API key (restrict it to the app in Google Cloud).
4. Yes, a daily quota (a search costs 100 units).
5. It finds videos, not audio files.
6. Video title, channel and thumbnails.
7. No.
8. **No.** Separating audio from video is prohibited by the YouTube API Services Terms, and background audio-only playback is not permitted.
9. Yes. The app opens the official YouTube app or page via `url_launcher`.
10. Only through the official player or embed.
11. No downloading, MP3 conversion, ad blocking or stream extraction. The app does none of these.
12. Yes.
13. Yes.
14. Yes.
15. Yes, as a link out.

Evidence: docs; no key was available. Results are parsed from documented response shapes and covered by mocked tests.

### Spotify Web API: Not suitable (today)
- New apps start in Development Mode (5 users, and the owner needs Premium). Extended quota is granted only to established, large apps.
- Preview URLs were removed for new apps.
- Playback requires the user's Premium account and Spotify's own SDK or embed.
- If quota is ever granted, it could serve as an external-player or metadata provider. `SPOTIFY_CLIENT_SECRET` must then live on a backend, never in the app.

### Deezer API: Preview only, subject to confirmation (not integrated)
- Search with no key at `api.deezer.com`, plus 30-second previews.
- Deezer's developer FAQ says developers get previews only, that streaming rights can change, and that commercial use may need an agreement.
- It was not integrated, to avoid relying on unclear commercial terms. Get written confirmation first.
- Docs only: the host is not on the sandbox allowlist.

### Last.fm: Requires commercial agreement
- Artist and track info plus tags; there is no audio.
- The API terms require permission for commercial use.
- Useful later for artist bios and similar artists. Not integrated.

### Radio Browser: Approved for implementation (Radio screen)
1. https://www.radio-browser.info
2. https://api.radio-browser.info
3. No key.
4. Free and community-run. Clients should pick a mirror and send a User-Agent.
5. Stations, not songs.
6. Name, country, language, tags and favicon.
7. No.
8. Live streams from each station's own server.
9. No.
10. Yes. The directory exists for players.
11. Each station streams under its own broadcast licence. Apple App Review (guideline 5.2.3) can ask for proof of streaming rights. Only `https` streams are used.
12. Yes (live: 17 Bangladesh stations, 12 Bengali-language stations).
13. Yes.
14. Yes.
15. Yes, as a separate feature that never appears in song search. **Live-verified.**

### Shadhin Music: Unavailable (partner access only)
- There is no public developer API, and no private endpoints were reverse-engineered.
- Requirements, if pursued: a business partnership with Shadhin (Bangladesh) covering catalogue licensing and an approved integration.
- The `MusicSource` interface is the adapter point. Keep it disabled until authorised.

### Gaana: Unavailable
- There is no official public developer API.
- Community projects use private endpoints and are unsuitable for production.

### Others investigated

| Provider | Finding |
|---|---|
| SoundCloud | The official API needs app registration and approval. Rights vary by uploader. |
| Audiomack | The API is open to approved partners only. |
| Bandcamp | The API is limited to labels and merchandise fulfilment partners (bandcamp.com/developer). |
| Openverse | It indexes CC audio, but the music is effectively Jamendo-hosted. Anonymous requests were throttled for hours. |
| Freesound | Sound effects and samples. API commercial use requires an agreement with UPF/MTG. |
| Pixabay, Mixkit | No music API found (the Pixabay API covers images and video). |
| Musopen | No public API found. |
| Openwhyd | It aggregates YouTube and SoundCloud links. Use those official players directly instead. |

## Bangla coverage

These are the honest expectations from the live runs (`test_live/`).

**Results by provider:**
- **Audius** returns real results for many Bangladeshi bands and solo artists, such as Shironamhin, Warfaze, Artcell, Aurthohin, Arnob, Habib Wahid, Tahsan, James and Fossils. Coverage of specific *songs* is patchy.
- **Apple iTunes** identifies most of the listed songs and artists (metadata only).
- **Internet Archive** has a few old or public-domain Bengali recordings.
- **Radio Browser** offers many Bangladeshi and Bengali-language stations.

**What is not covered:**
- The big Bangla catalogues (JioSaavn, Shadhin, Gaana, Spotify, YouTube Music) **cannot** be streamed in-app without commercial agreements.
- For those songs the app shows "Original recording unavailable". It then offers the official Apple Music page and, when a key is set, the official YouTube video.

## Credentials and secrets

See `docs/API_SETUP.md`.

**Public client identifiers:** `JAMENDO_CLIENT_ID` and `YOUTUBE_API_KEY` are public identifiers compiled into the app.
- Restrict the YouTube key to your package and bundle ids and web origins in Google Cloud.
- They are never committed.

**Server-only secrets:** `SPOTIFY_CLIENT_SECRET`, `LASTFM` shared secrets and similar must only ever live on a backend (for example the licence server in `server/`). They are not used by the app today.
