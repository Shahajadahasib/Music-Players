# Remaining limitations and third-party costs

## Product limitations (honest list)

1. **Mainstream catalogue.** Free, commercially usable APIs don't provide
   full-length major-label music. Popular songs are *identified* (Apple
   catalogue) and *linked out*. They aren't streamed unless an independent or
   open version of the *same recording* exists. Streaming the full mainstream
   catalogue needs paid label/publisher licences or a B2B music provider.
2. **Provider terms not yet confirmed in writing.** Audius and the Internet
   Archive are integrated on the basis of their public terms. Get written
   confirmation before selling (see COMMERCIAL_CHECKLIST.md).
3. **Lyrics are not available.** They were removed because they were fake.
   Licensed lyrics need a paid provider.
4. **No offline downloads.** No integrated provider licenses offline storage.
   Local files the user owns play offline.
5. **Local file metadata** comes from the file name (`Artist - Title.mp3`). ID3
   and MP4 tags and embedded artwork are not read yet (a candidate package is
   `audio_metadata_reader`). On the web, picked files last for the session only.
6. **Licence revocation.** The server publishes revoked licence ids, but the app
   doesn't poll them yet. Refunded web keys keep working offline until you add a
   periodic check. Store refunds are re-checked only when the store re-delivers
   the purchase.
7. **Apple JWS verification.** The server trusts App Store Server API responses
   received over TLS, and decodes but does not verify the certificate chain of
   `signedTransactionInfo`. Add chain verification (Apple's
   `app-store-server-library`) if you need defence in depth.
8. **Single-instance licence store.** `server/` stores issued keys in a JSON
   file. Use a database before running more than one replica.
9. **Fonts.** `google_fonts` downloads Plus Jakarta Sans at runtime and falls
   back to the system font offline. For a zero-third-party-request build, add
   the font files under `assets/google_fonts/` and set
   `GoogleFonts.config.allowRuntimeFetching = false`.
10. **Artwork-tinted backgrounds** use a palette accent seeded by the title, not
    colours extracted from the artwork.
11. **Not run on physical devices in this environment.** Android and iOS builds
    are compiled in CI, but real-device playback, lock-screen controls and store
    purchases still need the manual checklist in TESTING.md. The provider APIs
    could not be reached from the build sandbox, so live API behaviour (exact
    response fields, CORS, rate limits) must be confirmed on first run.
12. **Application id / bundle id** are still `com.example.music_player_app`.
    Change them before publishing (DEPLOYMENT.md §3).
13. **Brand.** "Aurora Music" is a placeholder name and the icon is the original
    repository's. Check trademarks.

## Third-party costs

| Item | Cost (check current prices) | Required? |
|---|---|---|
| Apple Developer Program | US$99 / year | For iOS |
| Google Play developer account | US$25 one-time | For Android |
| Apple / Google commission on IAP | 15% (small-business programmes) to 30% | Per sale |
| Stripe (web sales) | About 2.9% + 30¢ per card payment in the US (varies by country) | For web sales |
| Sales tax / VAT handling | Stripe Tax ≈ 0.5% per transaction, or an accountant | For web sales |
| Licence server hosting | US$0–10 / month (Fly.io, Cloud Run, Render free/hobby tiers) | Web sales / receipt checks |
| Web hosting | US$0 (Firebase Hosting, Netlify, Cloudflare Pages free tiers) | For web |
| Audius API | Free tier; paid plans exist for higher limits | Free to start |
| Internet Archive, iTunes Search API | Free | — |
| Jamendo commercial licence | Quote from Jamendo | Only if you enable Jamendo |
| Licensed lyrics (Musixmatch / LyricFind) | Commercial quote | Only if you add lyrics |
| Crash reporting (Sentry / Crashlytics) | Free tiers available | Optional |
| Legal review (terms, privacy, provider agreements) | Varies | Strongly recommended |
| Trademark search / registration | Varies by country | Recommended |
