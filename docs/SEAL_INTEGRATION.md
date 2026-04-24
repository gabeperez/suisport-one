# Seal integration plan

**Status:** researched, not implemented. See recommendation at the bottom.

## What Seal is

[Seal](https://github.com/MystenLabs/seal) is Mysten Labs' decentralized secrets management system for Sui dapps. It is **identity-based threshold encryption** — data is encrypted against an identity string of the form `[packageId][innerId]`, and per-identity decryption keys are held by a configurable set of key servers. A Move `seal_approve*` function in your package defines the access policy; key servers release a key share only after a Sui full node confirms the requester passes that policy. Threshold encryption means `t` of `n` key servers must cooperate to decrypt.

For SuiSport's shape — private GPS traces, heart-rate data, workout photos — Seal is the right primitive. Users control access through Move objects they already own (`UserProfile`, `Workout`), and the key-release path is enforced by the Sui consensus layer rather than a backend the user has to trust.

## The integration shape (when we do it)

### Move (new entry functions)

Inside the `suisport` package, add:

```move
public entry fun seal_approve_owner(
    id: vector<u8>,
    workout: &Workout,
    ctx: &TxContext
) {
    // Fail the entire dry-run if the caller isn't the owner.
    assert!(tx_context::sender(ctx) == workout.owner, 0);
    // Bind the Seal identity to *this* workout — the inner id must
    // prefix with the workout object id so a key for workout A can't
    // decrypt workout B.
    let prefix = object::uid_to_bytes(&workout.id);
    assert!(bytes_starts_with(&id, &prefix), 1);
}

public entry fun seal_approve_shared(
    id: vector<u8>,
    workout: &Workout,
    share_list: &ShareList,
    ctx: &TxContext
) {
    let sender = tx_context::sender(ctx);
    assert!(
        sender == workout.owner ||
        share_list.contains(sender),
        0
    );
    // ... same id-prefix check
}
```

`ShareList` is a versioned shared object (follow the pattern from `move/patterns/sources/whitelist.move` in the Seal repo). The workout owner holds a `Cap` object to mutate it.

### Envelope encryption (on iOS)

Don't encrypt 10 MB of GPX bytes through Seal directly. Use envelope encryption:

1. iOS generates a fresh AES-256-GCM key per workout.
2. Encrypts the workout blob with AES-256-GCM locally.
3. Uploads ciphertext to R2 / Walrus — backend and infra never see plaintext.
4. Encrypts only the 32-byte AES key via Seal against identity `[packageId][workoutIdBytes || nonce]`.
5. Stores the Seal-encrypted key either inline on the Sui `Workout` object or as a small sidecar blob referenced from it.

On read:
1. Client gets a `SessionKey` (user signs once per package-id, 10-min TTL).
2. Client builds a PTB calling `seal_approve_owner` (or `seal_approve_shared`).
3. Seal client fetches key shares from `t` of `n` servers, reconstructs, returns plaintext AES key.
4. Client decrypts the R2/Walrus blob locally.

### Sharing with a friend

Owner calls `add(&mut ShareList, &Cap, friend_address)`. No re-encryption, no re-upload. Next time the friend requests the Seal key, the updated allowlist grants access. **Revocation is not retroactive** — anyone who already decrypted can't be locked out of content they already have. Standard limitation of client-side crypto.

## The real blocker: no iOS SDK

`@mysten/seal` is TypeScript. There is no official Swift binding. Options, from least-good to best:

| Option | Trust model | Effort | Recommendation |
|---|---|---|---|
| Server-side proxy (Worker calls Seal) | Worker sees plaintext — **kills non-custodial property**. | Low | ❌ No. Destroys the reason to use Seal. |
| Hidden WebView running @mysten/seal | Same as TS SDK (client-side). | Medium (~200 LOC bridge) | OK as a tactical path |
| UniFFI wrap of Seal's Rust crates | Same as TS SDK. | High (port work) | Best long-term |
| Wait for official Swift/Kotlin SDK | — | None | Good if Mysten ships one |

The Seal Rust crates at `github.com/MystenLabs/seal/crates` are where the key-server client lives; UniFFI can expose them to Swift without a full port. This is the strongest candidate for a real integration and is where I'd start.

## Gotchas worth flagging now

- **No audit log.** Seal key servers don't emit on-chain evidence of key delivery. For GDPR / HIPAA-adjacent health-data scenarios we'd want our own telemetry.
- **Ciphertext size isn't hidden.** Pad if GPS trace length or HR sample count is sensitive.
- **Full-node propagation lag.** New `Workout` objects may return `InvalidParameter` for a few seconds after creation — client retry logic required.
- **Fixed server set per ciphertext.** If we pick a 3-of-5 committee and 3 of them shut down, those blobs are unrecoverable. Envelope encryption lets us rewrap the AES keys with a fresh committee; historical blobs remain bound to their original set.
- **Testnet key servers are explicitly not durable.** Mysten's warning: *"Avoid using them to encrypt data you expect to access reliably in the future."*
- **Package upgrades can silently change policy.** If our `suisport` package is upgradeable, users implicitly trust whoever holds the upgrade cap. Consider making the `seal_approve*` module immutable or governance-controlled.

## Recommendation

**Defer** the Seal integration. Reasons:

1. Testnet key servers are explicitly not durable — encrypting testnet data with Seal only trains us on the API; the encrypted blobs would be discarded anyway.
2. No iOS SDK means we'd build a bridge (WebView or UniFFI) before getting any user value. That bridge is real work we'd redo when Mysten ships a native SDK.
3. None of SuiSport's *current* features require encryption. Public workout sharing is the default. Private workouts are a future feature, not a current one.

**What to do in the meantime:**

- [ ] Add a `privacy_level` column to `workouts` now (public / followers / private) so we have the data model ready.
- [ ] When a workout is marked `private`, encrypt the GPX/photo blob client-side with AES-256-GCM and a locally-stored key. Store ciphertext in R2 as usual.
- [ ] Keep the AES key in the iOS Keychain for now; sync across the user's devices via CloudKit or iCloud Keychain.
- [ ] Document the deferred Seal migration path so we can swap the key-storage layer without touching encryption at rest.

This gives us a real privacy story without taking on the SDK-gap work up front. When Mysten publishes a Swift SDK — or when we hit a user need that actually requires threshold decryption (shared private workouts with friends on-chain) — we plug Seal in behind the same iOS interface.

## References

- Seal repo: https://github.com/MystenLabs/seal
- Design doc: https://github.com/MystenLabs/seal/blob/main/docs/content/Design.mdx
- Using Seal: https://github.com/MystenLabs/seal/blob/main/docs/content/UsingSeal.mdx
- Security best practices: https://github.com/MystenLabs/seal/blob/main/docs/content/SecurityBestPractices.mdx
- Pricing + key servers: https://github.com/MystenLabs/seal/blob/main/docs/content/Pricing.mdx
- `@mysten/seal` on npm: https://www.npmjs.com/package/@mysten/seal
- Move patterns: https://github.com/MystenLabs/seal/tree/main/move/patterns
