# Commercial licensing and compliance checklist

Work through this before taking the first payment. Items marked ⚖️ need a
lawyer or written confirmation from the third party.

## Music rights
- [ ] ⚖️ **Audius**: read the current API Terms and Open Music Licence. Get written
      confirmation that a **paid** app (one-time purchase) may stream Audius
      content to users. Register an API key / `app_name` for production.
- [ ] ⚖️ **Internet Archive**: confirm that your use (streaming PD / CC BY / CC BY-SA
      items in a paid app) is acceptable. Keep the licence filter, and keep the
      in-app licence display for attribution. Set up a process to handle takedown
      requests quickly (uploader-declared licences can be wrong).
- [ ] ⚖️ **Apple iTunes Search API**: metadata and store links in a paid app. Keep
      `ITUNES_PREVIEWS=false` unless counsel approves previews as "promotional".
      Consider joining the Apple Services Performance Partners affiliate programme.
- [ ] **Jamendo**: either keep it disabled, or sign a commercial agreement
      (licensing@jamendo.com) and only then set `JAMENDO_COMMERCIAL_AGREEMENT=true`.
- [ ] Do **not** add Deezer, Spotify, SoundCloud or YouTube as stream sources without a signed agreement.
- [ ] Lyrics: none are shown. If you add them, use a licensed provider (Musixmatch, LyricFind).
- [ ] Geographic availability: confirm each provider allows use in every country you sell in.
- [ ] Offline downloads: **not offered**. None of the integrated providers grants offline storage rights.

## Product claims and store listings
- [ ] Store descriptions must not promise "all music", "any song", "Spotify / Apple Music library" etc.
      Suggested wording: *"Search once — we find songs across independent and open music services
      and play the best authorised source. Mainstream songs you can't stream here link out to Apple Music."*
- [ ] Screenshots show real content and the availability badges.
- [ ] Premium is described as **app features** (unlimited playlists, local files, sleep timer, themes),
      not as access to music.
- [ ] Choose a brand name and icon you have rights to. "Aurora Music" is a placeholder:
      ⚖️ run a trademark search in your markets.
- [ ] Credit providers in the app (done: badges, Now Playing attribution, About page) and in the store listing.

## Payments
- [ ] Google Play: Merchant account; in-app product `premium_lifetime`; refund policy.
- [ ] Apple: Paid Apps agreement; non-consumable `premium_lifetime`; *Restore Purchases* is visible (done).
- [ ] Web: Stripe account; a one-time price; tax settings (Stripe Tax or manual VAT/GST registration);
      terms of sale and refund policy on the checkout page.
- [ ] ⚖️ Platform rules: on iOS and Android, digital features must be sold through the store's IAP.
      The app only offers the web checkout on the web build (done). Check current rules if you want
      to link out to web purchase from mobile in specific regions.
- [ ] Decide on refunds and chargebacks: add refunded licence ids to the server's revocation list.

## Privacy and security
- [ ] Publish PRIVACY.md (adapt it) at a public URL. Set `PRIVACY_POLICY_URL`.
- [ ] Play *Data safety* form and Apple *App Privacy* labels: no data collected by the developer.
      Third-party providers receive search queries and IP addresses.
- [ ] GDPR/UK GDPR: the in-app "Delete all my data" exists. The licence server stores the Stripe
      session id, licence id and a hashed e-mail reference; document the retention period (e.g. 7 years for tax).
- [ ] Secrets only on the server (Stripe secret, webhook secret, signing key, store credentials) in a
      secret manager. Rotate the signing key if it leaks (ship the new public key; old keys stop verifying).
- [ ] Bundle fonts locally if you want zero runtime calls to Google (see LIMITATIONS.md).
- [ ] If you add crash reporting, update the privacy policy and store disclosures.

## Accessibility and quality
- [ ] Run the manual device checklist in docs/TESTING.md on Android, iOS and Web.
- [ ] Test with TalkBack, VoiceOver and the largest system font size.
- [ ] Check contrast on the light theme with your final brand colours.
