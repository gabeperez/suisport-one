# SuiSport Privacy Policy

**Template — not legal advice. A lawyer must review before shipping.**
Last updated: `[DATE]`

This policy describes what data SuiSport (the "App" or "we") collects
from you, how it's used, how long it's kept, and how you can get it
deleted. Applies to use of the SuiSport iOS app and `suisport.app`
websites, operated by `[LEGAL ENTITY NAME, ADDRESS]`.

## What we collect

- **Workout data from Apple HealthKit.** With your explicit permission,
  we read workouts you already record in Apple Health — type, duration,
  distance, pace, heart rate, calories, and start/end timestamps. We do
  not read any non-workout health data (e.g. menstrual cycles, sleep,
  medical records) even if it's available.
- **Identity from OAuth.** When you sign in with Google or Apple, the
  provider shares your email, display name, and a stable user id. We use
  these to create your athlete profile. If you sign in with zkLogin via
  Enoki, the Sui address derived from your id token becomes your
  permanent identifier.
- **Profile data you enter.** Display name, handle, bio, location, and
  an optional profile photo.
- **Social activity.** Kudos, comments, follows, mutes, and reports you
  create, along with anything someone else does to your activity.
- **Device info.** Bundle id and App Attest key id so we can verify
  requests originate from an unmodified copy of the SuiSport app.
- **Operational logs.** Cloudflare Worker request logs containing IP
  addresses, request paths, and response codes. Retained 30 days then
  deleted.

We do **not** collect:
- Location traces (we don't record GPS — Apple Health does).
- Contacts, photos outside the profile picker, microphone audio, or
  browsing history.
- Any health data other than the workout types listed above.

## How we use it

- Display your feed, profile, clubs, challenges, segments, and trophies.
- Compute your Sweat Points and streak.
- Issue on-chain proofs of workouts (anchored to Sui + stored on
  Walrus). These are pseudonymous — tied to your Sui address, not
  your name.
- Prevent abuse (rate limiting, replay protection, pace sanity checks).
- Respond to legal process.

We do **not**:
- Sell your data to third parties.
- Use your data to train third-party AI models.
- Show third-party advertising.

## On-chain data

Workout attestations and $SWEAT balances live on the Sui blockchain.
Workout data blobs live on Walrus. Both are public and, by design,
**cannot be deleted** once written. We mitigate this by storing the
minimal hash of each workout on-chain, not raw sensor data. Raw sensor
data is encrypted at rest in our backend and deleted when you delete
your account — the on-chain hash remains but it's uncorrelated with
your identity once our mapping is gone.

If you want no on-chain footprint, do not submit workouts for
verification.

## Who sees what

- **Your feed** is visible to anyone who follows you and, for public
  clubs, anyone in those clubs.
- **Your profile** (handle, display name, bio, stats) is visible to
  anyone who navigates to it.
- **Your location** (e.g. "Brooklyn, NY") is visible if you enter it.
- **Your Sui address** is public. Anyone can view its balance.
- **Your OAuth email** is never shown to other users.
- **App Attest key ids** are never shown to other users.

## Third parties we share data with

- **Cloudflare** — hosts our API, database, and media. Their privacy
  policy: `[https://www.cloudflare.com/privacypolicy/]`.
- **Mysten Labs (Enoki, Sui, Walrus)** — zkLogin, on-chain attestation,
  decentralized blob storage. Their privacy policy: `[URL]`.
- **Google / Apple** — only during OAuth sign-in.

We do not use third-party analytics or advertising SDKs.

## Retention

- **Workout data:** kept until you delete your account.
- **Feed items (kudos, comments):** kept until you or the authoring user
  deletes them.
- **Sessions:** 30-day expiry; revoked on sign-out.
- **App Attest receipts:** 1 year (for fraud investigation).
- **Suspect activity log:** 1 year then rotated.
- **Cloudflare request logs:** 30 days.
- **On-chain data (Sui, Walrus):** retained indefinitely and outside our
  control — see "On-chain data".

## Your rights

- **Access:** `GET /v1/me/export` returns a JSON dump of every row we
  have that belongs to you. Available in-app: Profile → Settings →
  Export my data.
- **Delete:** `DELETE /v1/me` hard-deletes your server-side data.
  Available in-app: Profile → Settings → Delete account. On-chain data
  cannot be deleted; see "On-chain data".
- **Correction:** edit your profile in the app.
- **Portability:** the export is JSON; import into any other service.
- **Objection / restriction / withdrawing consent:** contact us at
  `[privacy@suisport.app]`.
- **GDPR / CCPA complaints:** contact your local data protection
  authority.

## Children

SuiSport is not intended for children under 13. Apple HealthKit itself
requires users to be 13+. We do not knowingly collect data from anyone
under 13. If we discover we have, we delete it.

## Security

- All traffic is HTTPS.
- OAuth tokens are validated against the issuer's JWKS.
- Mutating requests are rate-limited by caller.
- Sensitive operations (workout submission) require App Attest
  verification.
- We follow responsible disclosure for security reports — contact
  `[security@suisport.app]`.

## Breach notification

If we suffer a data breach likely to harm you, we'll notify you within
72 hours of becoming aware, by the contact info we have (email +
in-app).

## Changes

We'll announce material changes in the app and by pushing a dated new
version of this page. Your continued use after changes means you accept
the new policy.

## Contact

`[LEGAL ENTITY NAME]`
`[ADDRESS]`
`[privacy@suisport.app]`
