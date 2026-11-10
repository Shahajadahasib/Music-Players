# Aurora licence server

A small Dart (shelf) service that:

1. **Sells on the web.** It receives Stripe `checkout.session.completed`
   webhooks and issues an Ed25519-signed licence key. The buyer's success page
   fetches the key.
2. **Optionally verifies store purchases.** The app posts Google Play purchase
   tokens or App Store transaction ids. The server confirms them with Google or
   Apple.

The app verifies licence keys **offline** with the public key. If this server
is down, existing customers are unaffected.

## Endpoints

| Method | Path | Caller | Notes |
|---|---|---|---|
| GET | `/healthz` | uptime checks | |
| POST | `/v1/stripe/webhook` | Stripe | Signature-checked, 5-minute replay window, idempotent per session |
| GET | `/v1/licenses/checkout/{sessionId}` | your success page | 404 until the webhook arrives, so poll for about 10 s |
| POST | `/v1/licenses/verify-store` | the app | `{platform: android\|ios, productId, purchaseId, verificationData}` → `{valid}`. 503 when the store can't be reached |
| GET | `/v1/licenses/revoked` | (future) the app | Revoked licence ids |

## Configuration (environment variables; store them in a secret manager)

| Variable | Required | Description |
|---|---|---|
| `LICENSE_SIGNING_KEY` | ✅ | Base64 32-byte Ed25519 seed from `dart run bin/keygen.dart`. **Secret.** |
| `PRODUCT_ID` | | Default `premium_lifetime` |
| `STRIPE_WEBHOOK_SECRET` | web sales | `whsec_…` from the Stripe dashboard |
| `ALLOWED_ORIGIN` | web sales | e.g. `https://app.example.com` (CORS for the success page) |
| `DATA_DIR` | | Where `licenses.json` is kept (mount a volume) |
| `GOOGLE_SERVICE_ACCOUNT_JSON`, `ANDROID_PACKAGE_NAME` | Android checks | The service account needs *View financial data* in Play Console |
| `APPLE_ISSUER_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, `APPLE_BUNDLE_ID`, `APPLE_ENVIRONMENT` | iOS checks | In-App Purchase key (.p8) from App Store Connect. Set `APPLE_ENVIRONMENT=sandbox` for TestFlight |
| `PORT` | | Default 8080 |

## Run

```bash
dart pub get
dart test
dart run bin/keygen.dart
LICENSE_SIGNING_KEY=… STRIPE_WEBHOOK_SECRET=… dart run bin/server.dart
```

Docker:

```bash
docker build -t aurora-license .
docker run -p 8080:8080 -v aurora-data:/data --env-file .env aurora-license
```

Issue a key by hand (for support): `LICENSE_SIGNING_KEY=… dart run bin/issue_license.dart`.

## Web checkout flow

1. In Stripe, create a product with a **one-time** price and a Payment Link. Set
   its success URL to `https://your-site/licence?session_id={CHECKOUT_SESSION_ID}`.
2. The `/licence` page calls `GET /v1/licenses/checkout/<session_id>`, retrying
   for a few seconds, and shows the key with a copy button.
3. The customer pastes the key into **Settings → Premium → Have a licence key?**
4. Set `WEB_CHECKOUT_URL` in the app config to the Payment Link.

## Security notes

- The signing key never leaves the server. If it leaks, generate a new one, ship
  the new public key, and re-issue keys to customers.
- Keys carry a hashed customer reference, never an e-mail address.
- The request body limit is 64 KB, and every input is validated. Session ids
  must match `cs_…`.
- The JSON file store suits one instance. Use a database for more than one.
