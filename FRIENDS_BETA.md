# SuiSport — friends beta runbook

Everything you need to share the app with a handful of testers, deploy
changes, and roll things back.

## Production URLs

- **API:** `https://suisport-api.perez-jg22.workers.dev`
- **D1 DB:** `suisport-db` (uuid `285b1bc5-afd6-493d-abf3-096b95d450aa`, region `ENAM`)
- **R2 bucket:** `suisport-media`
- **CF account:** `Gabe Perez` (`1be5e8b0e95f6466ce392e3be13d816b`)
- **Admin token:** stored as Worker secret (`wrangler secret list` in `cloudflare/` to confirm). Rotate with `echo "<new>" | wrangler secret put ADMIN_TOKEN`.

## Deploy

```sh
cd cloudflare
wrangler deploy              # publishes to workers.dev
```

Once GitHub Actions is live, a push to `main` auto-deploys. Add these repo secrets:
- `CLOUDFLARE_API_TOKEN` — scoped to *Workers Scripts: Edit* + *D1: Edit* + *R2: Edit* on your account
- `CLOUDFLARE_ACCOUNT_ID` — `1be5e8b0e95f6466ce392e3be13d816b`

## Rollback

Every deploy creates a new version. Roll back via dashboard or:
```sh
wrangler deployments list
wrangler rollback <deployment-id>
```

## Schema changes

Add new migrations under `cloudflare/migrations/0002_<name>.sql`, then:
```sh
cd cloudflare
npm run db:migrate       # applies pending migrations to remote
npm run db:migrate:list  # shows state
```

The existing `schema.sql` is the one-shot bootstrap; `migrations/` is the
ongoing source of truth.

## Demo data

```sh
# Check current state (needs ADMIN_TOKEN)
curl -H "X-Admin-Token: $TOKEN" https://suisport-api.perez-jg22.workers.dev/v1/admin/status

# Wipe everything tagged is_demo=1
curl -X POST -H "X-Admin-Token: $TOKEN" https://suisport-api.perez-jg22.workers.dev/v1/admin/clear-demo

# Reseed
cd cloudflare && npm run db:seed
```

## Logs / live tail

```sh
cd cloudflare
wrangler tail              # stream realtime request logs
```

For structured archival: enable Logpush in the CF dashboard
(Workers → suisport-api → Settings → Logs → Logpush).

## Inviting friends to test the iOS app

Today: `xcodebuild` a `.ipa` from a real Apple Developer account and
distribute via TestFlight. Steps (needs $99/yr Apple Developer):
1. Xcode → iHealth target → Signing & Capabilities → set your team + bundle id.
2. Product → Archive.
3. Distribute App → App Store Connect → Upload.
4. Invite testers in App Store Connect → TestFlight.

Each build can hold up to 10k external testers for 90 days. Free option
for ≤ 3 devices: Xcode → Run on connected device (requires Mac + cable).

## What's stubbed — don't let testers stress-test these

- **Auth:** `/v1/auth/session` returns a deterministic SHA-256 of the id
  token as a fake Sui address. Real zkLogin (Enoki) is not wired yet, so
  anyone with a copied id token could impersonate. Fine for 5 friends,
  not fine for open beta.
- **App Attest:** we accept the payload but don't verify the signature.
  Someone with the API contract could bypass it.
- **$SWEAT minting:** `/v1/workouts` returns `txDigest: pending_<id>`.
  Nothing is actually on-chain. No real tokens.
- **Rate limit:** 60 req/min/IP. Plenty for 5 friends; tune if wider.
- **Moderation:** reports are logged to D1 but not reviewed. Mute
  actually hides feed items.

## What friends can actually do

- Sign in with Google/Apple (mocked zkLogin)
- Read a shared feed of 10+ seeded workouts + anything they add
- Give kudos with optional $SWEAT tip (counted server-side)
- Comment on feed items
- Create / join / leave clubs
- Join / leave challenges
- Star segments
- Add shoes to gear
- Mute / report
- Edit their profile (name, handle, bio, location, avatar tone)

## Known gaps before prod

Listed roughly in priority order — none block the beta, but don't ship
any of these to strangers:

- [ ] Real Enoki zkLogin (replace deterministic hash auth)
- [ ] App Attest verification (replace accept-all)
- [ ] Custom domain (`api.suisport.app`) — keep the `workers.dev` URL out of any UI copy
- [ ] Sentry iOS SDK + DSN
- [ ] CF Logpush → R2 for log archival
- [ ] Walrus upload pipeline
- [ ] Sui PTB submission via Enoki sponsored tx
- [ ] Move contracts audited + deployed to mainnet
- [ ] Privacy policy + Terms of Service pages
- [ ] GDPR delete-my-account flow
- [ ] iOS crash reporting (Crashlytics or Sentry)
- [ ] Deployed on both the iPhone AND iPad size classes
- [ ] App icon (default Xcode template today)
- [ ] App Store screenshots + metadata

## Emergency disable

If something goes catastrophically wrong:
```sh
# Kill the worker entirely
wrangler delete suisport-api
```

Nuclear option, but the D1 DB and R2 bucket will remain — you can
redeploy with `wrangler deploy` from the same directory.
