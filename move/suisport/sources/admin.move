/// Administrative + oracle capabilities, plus emergency pause.
///
/// `AdminCap` is intended to be held by a Sui multisig (2-of-3 or 3-of-5 mixing
/// Ed25519 + Secp256r1 keys). `OracleCap` is held by the backend attestation
/// signer — its public key is stored on-chain and verified inside
/// `rewards_engine::submit_workout`, so leaking the private key has a
/// bounded blast radius governed by on-chain rate limits.
module suisport::admin {
    use sui::event;
    use sui::transfer;
    use sui::tx_context::TxContext;

    /// Capability held by the multisig that governs the protocol.
    public struct AdminCap has key, store {
        id: UID,
    }

    /// Capability held by the backend attestation signer (reference, not a signer).
    /// The public key is what's checked on-chain.
    public struct OracleCap has key, store {
        id: UID,
        pubkey: vector<u8>,
        revoked: bool,
    }

    // ---- Events ----
    public struct OraclePubkeyRotated has copy, drop { old: vector<u8>, new: vector<u8> }
    public struct OracleRevoked has copy, drop {}

    /// Create the two capabilities on module publish. Both are transferred to
    /// the publisher; the publisher should immediately transfer them to the
    /// multisig / HSM addresses in a follow-up PTB.
    fun init(ctx: &mut TxContext) {
        let admin = AdminCap { id: object::new(ctx) };
        transfer::public_transfer(admin, ctx.sender());
    }

    /// Called once from the multisig after the oracle's Ed25519 pubkey is generated.
    public fun mint_oracle(_admin: &AdminCap, pubkey: vector<u8>, ctx: &mut TxContext): OracleCap {
        OracleCap { id: object::new(ctx), pubkey, revoked: false }
    }

    public fun rotate_oracle(_admin: &AdminCap, oracle: &mut OracleCap, new_pubkey: vector<u8>) {
        let old = oracle.pubkey;
        oracle.pubkey = new_pubkey;
        oracle.revoked = false;
        event::emit(OraclePubkeyRotated { old, new: new_pubkey });
    }

    public fun revoke_oracle(_admin: &AdminCap, oracle: &mut OracleCap) {
        oracle.revoked = true;
        event::emit(OracleRevoked {});
    }

    public fun oracle_pubkey(o: &OracleCap): vector<u8> { o.pubkey }
    public fun oracle_revoked(o: &OracleCap): bool { o.revoked }
}
