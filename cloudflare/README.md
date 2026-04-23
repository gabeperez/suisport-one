# SuiSport Cloudflare backend

Workers + D1 + R2 stack that serves the iOS app.

**Base URL:** `https://suisport-api.perez-jg22.workers.dev`

## Resources

- **D1 database** `suisport-db` (uuid `285b1bc5-afd6-493d-abf3-096b95d450aa`), region `ENAM`
- **R2 bucket** `suisport-media` (region `ENAM`) — profile photos, club banners, pre-attestation drafts
- **Worker** `suisport-api` — Hono app in `src/`, bound as `env.DB` + `env.MEDIA`

## Local dev

```sh
cd cloudflare
npm install
wrangler dev               # local Worker, talks to remote D1 + R2 by default
```

## Deploy

```sh
wrangler deploy
```

## Schema + seed

Schema is in `schema.sql` (25 tables). Demo data is in `seed.sql` — every
seeded row is tagged `is_demo = 1`.

```sh
npm run db:schema           # (re)apply schema
npm run db:seed             # load demo fixtures
npm run db:clear-demo       # wipe every is_demo=1 row, parent tables last
```

## Admin endpoints (require `X-Admin-Token`)

Set the token in `wrangler.toml` or with `wrangler secret put ADMIN_TOKEN`.

```sh
# Current state of every table + how many rows are demo
curl -H 'X-Admin-Token: <token>' https://suisport-api.perez-jg22.workers.dev/v1/admin/status

# Clear all demo data
curl -X POST -H 'X-Admin-Token: <token>' https://suisport-api.perez-jg22.workers.dev/v1/admin/clear-demo
```

## Public API shape (v1)

| Method | Path | Purpose |
|---|---|---|
| POST | `/v1/auth/session` | Exchange OAuth id token for session (stubbed zkLogin — deterministic address) |
| GET | `/v1/me` | Current athlete |
| PATCH | `/v1/me` | Update profile fields |
| GET | `/v1/athletes` | List |
| GET | `/v1/athletes/:id` | One |
| GET | `/v1/athletes/:id/trophies` | Unlock state + showcase slots |
| GET | `/v1/athletes/:id/shoes` | Gear |
| GET | `/v1/athletes/:id/prs` | Personal records |
| GET | `/v1/athletes/:id/sweat` | Points + streak |
| GET | `/v1/feed?sort=recent\|kudos&limit=50` | Feed |
| POST | `/v1/feed/:id/kudos` | Kudos (optional `{tip}` in body) |
| DELETE | `/v1/feed/:id/kudos` | Undo |
| POST | `/v1/feed/:id/comments` | Add comment |
| GET | `/v1/feed/:id/comments` | List comments |
| POST | `/v1/follow/:id` / DELETE | Follow toggle |
| POST | `/v1/mute/:id` | Mute an athlete |
| POST | `/v1/report` | Report feed item or athlete |
| GET | `/v1/clubs?filter=all\|joined\|brands` | Clubs |
| GET | `/v1/clubs/:id` | One club |
| POST | `/v1/clubs` | Create club |
| POST | `/v1/clubs/:id/membership` / DELETE | Join / leave |
| GET | `/v1/challenges` | List |
| POST | `/v1/challenges/:id/join` / DELETE | Join / leave |
| GET | `/v1/segments` | List |
| GET | `/v1/segments/:id/leaderboard` | Top 50 efforts |
| POST | `/v1/segments/:id/star` / DELETE | Star toggle |
| POST | `/v1/shoes` | Add shoe |
| POST | `/v1/shoes/:id/retire` | Toggle retired |
| POST | `/v1/workouts` | Submit (attestation pipeline STUBBED — returns `txDigest: pending_...`) |
| GET | `/v1/workouts/:id` | Fetch |
| PUT | `/v1/media/upload/:kind/:id` | Raw bytes → R2 (kinds: `avatar`, `club`, `workout`) |
| GET | `/v1/media/*` | Serve R2 object back |

## Authentication

Mocked for now: while there's no session token, pass `?athleteId=0xdemo_me`
on the request to masquerade as the demo user. The `sessionMiddleware`
strips this path in production (gated on a demo-id prefix check). Real
zkLogin via Enoki is on the punch list; wiring lives in `src/routes/auth.ts`.

## Demo data

Everything seeded in `seed.sql` is tagged `is_demo = 1` on every row. Run
`npm run db:clear-demo` (or `POST /v1/admin/clear-demo`) to wipe it. The
schema_meta table tracks `demo_seeded` so the iOS app can decide whether
to hide the "demo data" banner.

**Current demo surface:** 13 athletes, 10 feed items/workouts, 6 clubs, 5
challenges, 5 segments, 8 trophies, 3 shoes, 4 PRs, plus seeded kudos,
comments, follows, and club memberships.

## What's stubbed

- **Enoki zkLogin:** `/v1/auth/session` returns a deterministic SHA-256 of
  the id token as a fake Sui address. The iOS app already accepts this
  shape. Replace the mock with a real Enoki `proveZkLogin()` call.
- **App Attest verify:** workout submissions accept an attestation
  payload but don't verify it.
- **Walrus upload:** `/v1/workouts` persists the workout in D1 but does
  not push the canonical blob to Walrus.
- **Sui PTB:** `txDigest` is a placeholder (`pending_<workoutId>`).
- **Durable Objects:** no live chat / real-time kudos yet.
- **Queues:** not bound; submit route runs synchronously.

To light up Queues + DO, uncomment the bindings in `wrangler.toml` and
pay $5/mo for Workers Paid.

## Cost at current scale

- Workers free (< 100k req/day): **$0/mo**
- D1 free (< 25B reads, < 50M writes): **$0/mo**
- R2 free (< 10 GB storage): **$0/mo**

Total today: **$0**.
