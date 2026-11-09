/// Build-time configuration, supplied with `--dart-define` (or
/// `--dart-define-from-file=config/release.json`).
///
/// Nothing here is a secret: everything compiled into a Flutter app can be
/// extracted from the binary / JavaScript bundle. Private credentials (store
/// service-account keys, Stripe secret keys, licence signing keys) live only
/// on the licence server — see `server/README.md`.
abstract final class AppConfig {
  // ── Branding ─────────────────────────────────────────────────────────────
  static const String appName =
      String.fromEnvironment('APP_NAME', defaultValue: 'Aurora Music');

  /// Sent to Audius as `app_name` (requested by Audius for production apps).
  static const String audiusAppName = String.fromEnvironment(
    'AUDIUS_APP_NAME',
    defaultValue: 'aurora-music-player',
  );

  /// Audius API host. Configurable because Audius has moved hosts before.
  static const String audiusHost =
      String.fromEnvironment('AUDIUS_API_HOST', defaultValue: 'api.audius.co');

  // ── Provider licensing switches ──────────────────────────────────────────
  //
  // A provider is only used as a *playback* source when its terms permit the
  // way this app is sold. See docs/PROVIDER_LICENSING.md.

  /// Jamendo's free API is for non-commercial use only. Set to true **only**
  /// after signing a commercial agreement with Jamendo (licensing@jamendo.com).
  static const bool jamendoCommercialAgreement =
      bool.fromEnvironment('JAMENDO_COMMERCIAL_AGREEMENT');

  /// Jamendo client id from https://devportal.jamendo.com.
  static const String jamendoClientId =
      String.fromEnvironment('JAMENDO_CLIENT_ID');

  /// iTunes Search API is used for catalogue metadata (titles, albums,
  /// artwork) to identify songs. Apple's terms only allow previews to be used
  /// to promote store content, so preview *playback* is off unless enabled
  /// here (and then always shown next to an "Open in Apple Music" link).
  static const bool itunesMetadata =
      bool.fromEnvironment('ITUNES_METADATA', defaultValue: true);
  static const bool itunesPreviews = bool.fromEnvironment('ITUNES_PREVIEWS');

  /// Storefront country for iTunes Search (ISO 3166-1 alpha-2).
  static const String itunesCountry =
      String.fromEnvironment('ITUNES_COUNTRY', defaultValue: 'US');

  /// Internet Archive items filtered to public-domain / CC0 / CC-BY licences.
  static const bool internetArchive =
      bool.fromEnvironment('INTERNET_ARCHIVE', defaultValue: true);

  // ── Licensing / purchase ─────────────────────────────────────────────────

  /// `freemium` — free tier + one-time "Premium" unlock (in-app purchase on
  ///              Android/iOS, licence key on Web).
  /// `paid`     — the app itself is sold as a paid download; everything is
  ///              unlocked and no purchase UI is shown.
  static const String licensingMode =
      String.fromEnvironment('LICENSING_MODE', defaultValue: 'freemium');

  static bool get isPaidUpfront => licensingMode == 'paid';

  /// Non-consumable product id configured in Play Console / App Store Connect.
  static const String premiumProductId = String.fromEnvironment(
    'PREMIUM_PRODUCT_ID',
    defaultValue: 'premium_lifetime',
  );

  /// Base64 Ed25519 public key that verifies licence keys issued by the
  /// licence server. Public by design — it can only *verify*, not sign.
  static const String licensePublicKey =
      String.fromEnvironment('LICENSE_PUBLIC_KEY');

  /// Optional licence server base URL (e.g. https://licence.example.com).
  /// When set, store purchases are verified server-side and the web checkout
  /// is available.
  static const String licenseServerUrl =
      String.fromEnvironment('LICENSE_SERVER_URL');

  /// Web checkout page (e.g. a Stripe Payment Link) for buying a licence key.
  static const String webCheckoutUrl =
      String.fromEnvironment('WEB_CHECKOUT_URL');

  static const String privacyPolicyUrl =
      String.fromEnvironment('PRIVACY_POLICY_URL');
  static const String supportEmail =
      String.fromEnvironment('SUPPORT_EMAIL');

  /// Free-tier limits.
  static const int freePlaylistLimit = 3;
}
