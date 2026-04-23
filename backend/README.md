# SuiSport Backend

Node 20+ / TypeScript / Fastify. The abstraction layer between iOS and the
chain stack. The iOS app never talks to Sui, Walrus, or Enoki directly.

## Responsibilities

1. **Session exchange** — take an Apple/Google `id_token`, call Enoki's zkLogin
   endpoint, return a SuiSport session JWT + derived Sui address.
2. **App Attest verification** — validate the per-device attestation + per-call
   assertion. Reject submissions that aren't signed by a genuine iOS device
   running our legitimate build.
3. **Plausibility checks** — pace, HR distribution, motion cross-validation,
   source-bundle pinning. Flag / downgrade dubious workouts before rewarding.
4. **Walrus upload** — accept the client's Seal-encrypted blob, PUT it to a
   Walrus publisher with `send_object_to = user_sui_address` so the Blob
   object is owned by the user. Monthly per-user Quilt batching in prod.
5. **Attestation signing** — sign a canonical BLAKE2b256 digest with the
   oracle's ed25519 key (HSM/KMS in prod). The on-chain `rewards_engine`
   verifies that signature before minting.
6. **Sponsored submit** — build a PTB calling
   `rewards_engine::submit_workout`, wrap with Enoki's sponsored-tx gas
   coins, return the digest to the client.

## Endpoints (v1)

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/auth/session` | Exchange OAuth id_token for zkLogin proof + Sui address. |
| `GET` | `/health/challenge` | Issues a short-TTL challenge for App Attest assertions. |
| `GET` | `/health/ping` | Liveness. |
| `POST` | `/workouts` | Submit a verified workout; mints $SWEAT on-chain. |

## Local dev

```bash
cp .env.example .env
# fill in ENOKI_API_KEY, ORACLE_*_KEY_HEX, SUI_*_ID
npm install
npm run dev
```

## Sequence: submitting a workout

```
iOS client                         Backend                          Sui / Walrus
    |                                  |                                 |
    |--GET /health/challenge---------->|                                 |
    |<-------------------{challenge}---|                                 |
    | (App Attest assertion            |                                 |
    |  over hash(payload || challenge))|                                 |
    |--POST /workouts----------------->|                                 |
    |                                  |-- verify assertion              |
    |                                  |-- plausibility checks           |
    |                                  |-- upload encrypted blob ------->|
    |                                  |<------------- walrus blob id ---|
    |                                  |-- sign ed25519 attestation      |
    |                                  |-- build PTB + sponsor gas------>|
    |                                  |<--- tx digest ------------------|
    |<-{digest, points, blobId}--------|                                 |
```

## Security notes

- **Oracle key** lives in an HSM / KMS, never the app process. The backend
  delegates signing to the KMS so a compromised Node process cannot mint.
- **Replay protection** is enforced on-chain via `rewards_engine::consumed_nonces`;
  the oracle key cannot double-sign with the same nonce successfully.
- **App Attest key enrollment** is one-time per install; verify the attestation
  chain against Apple's root CA once and persist only the validated pubkey.
- **Rate limits** at the edge (per-session, per-IP) layered on top of on-chain caps.
- **Challenge TTL** 120 s — swap the in-memory Map for Redis in production.
