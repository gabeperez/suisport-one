/// $SWEAT — the fungible reward token.
///
/// Uses the standard `coin::create_currency` pattern with a One-Time Witness.
/// The `TreasuryCap` is immediately moved into `rewards_engine::RewardsEngine`
/// and never held by a user key, so minting requires going through the
/// on-chain rate-limited entry functions in that module.
module suisport::sweat {
    use std::option;
    use sui::coin;
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::url;

    /// One-Time Witness. Its name MUST equal the module name uppercased.
    public struct SWEAT has drop {}

    /// Module initializer. Creates the currency and transfers capabilities.
    /// The `TreasuryCap` is transferred to the module publisher so they can
    /// hand it to `rewards_engine::init` in a follow-up PTB.
    fun init(witness: SWEAT, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency<SWEAT>(
            witness,
            9,                                                // decimals
            b"SWEAT",                                         // symbol
            b"Sweat",                                         // name
            b"Rewards for real, verified workouts on SuiSport.",
            option::some(url::new_unsafe_from_bytes(
                b"https://suisport.app/sweat-icon.png"
            )),
            ctx,
        );
        // Metadata is immutable and publicly readable. We never update it.
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, ctx.sender());
    }
}
