/// Version gate for upgrades. Every entry function reads the current shared
/// `Version` object and asserts it matches — so when the package is upgraded,
/// the admin bumps `Version` and old code paths stop accepting txs.
module suisport::version {
    use sui::transfer;
    use sui::tx_context::TxContext;

    public struct Version has key {
        id: UID,
        value: u64,
    }

    const EVersionMismatch: u64 = 1000;

    fun init(ctx: &mut TxContext) {
        transfer::share_object(Version { id: object::new(ctx), value: 1 });
    }

    public fun value(v: &Version): u64 { v.value }

    public fun assert_matches(v: &Version, expected: u64) {
        assert!(v.value == expected, EVersionMismatch);
    }

    /// Admin-only; caller must pass an `AdminCap` via a wrapper function in a future module.
    public(package) fun bump(v: &mut Version) { v.value = v.value + 1; }
}
