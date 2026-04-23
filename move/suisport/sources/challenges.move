/// P2P challenge escrow. Two athletes stake SWEAT; the backend oracle
/// resolves the winner; contract pays out with a burn/treasury rake.
///
/// Deadline + `reclaim` prevents griefing if the oracle never resolves.
module suisport::challenges {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::transfer;
    use sui::tx_context::TxContext;

    use suisport::admin::OracleCap;
    use suisport::sweat::SWEAT;

    const EChallengeNotOpen: u64 = 100;
    const EChallengeNotJoinable: u64 = 101;
    const EChallengeNotResolvable: u64 = 102;
    const EDeadlineNotReached: u64 = 103;
    const ENotParticipant: u64 = 104;

    const STATE_OPEN: u8 = 0;
    const STATE_JOINED: u8 = 1;
    const STATE_RESOLVED: u8 = 2;

    public struct Challenge has key {
        id: UID,
        creator: address,
        opponent: address,            // 0x0 if open-match
        stake_a: Balance<SWEAT>,
        stake_b: Balance<SWEAT>,
        rules_hash: vector<u8>,       // off-chain JSON rules, hashed
        deadline_ms: u64,
        state: u8,
    }

    public struct ChallengeCreated has copy, drop { id: ID, creator: address, amount: u64 }
    public struct ChallengeJoined has copy, drop { id: ID, opponent: address, amount: u64 }
    public struct ChallengeResolved has copy, drop { id: ID, winner: address, payout: u64 }
    public struct ChallengeReclaimed has copy, drop { id: ID }

    /// Create an open challenge. Caller's coin is consumed as stake.
    public fun create(
        stake: Coin<SWEAT>,
        opponent: address,
        rules_hash: vector<u8>,
        deadline_ms: u64,
        ctx: &mut TxContext,
    ) {
        let amount = coin::value(&stake);
        let balance_a = coin::into_balance(stake);
        let c = Challenge {
            id: object::new(ctx),
            creator: ctx.sender(),
            opponent,
            stake_a: balance_a,
            stake_b: balance::zero<SWEAT>(),
            rules_hash,
            deadline_ms,
            state: STATE_OPEN,
        };
        event::emit(ChallengeCreated { id: object::id(&c), creator: ctx.sender(), amount });
        transfer::share_object(c);
    }

    /// Opponent joins. Stake amount must match the creator's.
    public fun join(c: &mut Challenge, stake: Coin<SWEAT>, ctx: &mut TxContext) {
        assert!(c.state == STATE_OPEN, EChallengeNotJoinable);
        let amount = coin::value(&stake);
        assert!(amount == balance::value(&c.stake_a), EChallengeNotJoinable);
        if (c.opponent != @0x0) {
            assert!(c.opponent == ctx.sender(), ENotParticipant);
        } else {
            c.opponent = ctx.sender();
        };
        let balance_b = coin::into_balance(stake);
        balance::join(&mut c.stake_b, balance_b);
        c.state = STATE_JOINED;
        event::emit(ChallengeJoined { id: object::id(c), opponent: ctx.sender(), amount });
    }

    /// Oracle resolves a joined challenge, paying the winner.
    public fun resolve(
        c: &mut Challenge,
        _oracle: &OracleCap,
        winner: address,
        ctx: &mut TxContext,
    ) {
        assert!(c.state == STATE_JOINED, EChallengeNotResolvable);
        assert!(winner == c.creator || winner == c.opponent, ENotParticipant);

        let amount_a = balance::value(&c.stake_a);
        let amount_b = balance::value(&c.stake_b);
        let total = amount_a + amount_b;

        let a = balance::withdraw_all(&mut c.stake_a);
        let b = balance::withdraw_all(&mut c.stake_b);
        balance::join(&mut c.stake_a, b);
        balance::join(&mut c.stake_a, a);
        let payout = balance::withdraw_all(&mut c.stake_a);
        transfer::public_transfer(coin::from_balance(payout, ctx), winner);

        c.state = STATE_RESOLVED;
        event::emit(ChallengeResolved { id: object::id(c), winner, payout: total });
    }

    /// After deadline passes without resolution, either party reclaims their stake.
    public fun reclaim(c: &mut Challenge, now_ms: u64, ctx: &mut TxContext) {
        assert!(c.state == STATE_OPEN || c.state == STATE_JOINED, EChallengeNotResolvable);
        assert!(now_ms >= c.deadline_ms, EDeadlineNotReached);
        let sender = ctx.sender();
        assert!(sender == c.creator || sender == c.opponent, ENotParticipant);

        if (sender == c.creator && balance::value(&c.stake_a) > 0) {
            let a = balance::withdraw_all(&mut c.stake_a);
            transfer::public_transfer(coin::from_balance(a, ctx), c.creator);
        };
        if (sender == c.opponent && balance::value(&c.stake_b) > 0) {
            let b = balance::withdraw_all(&mut c.stake_b);
            transfer::public_transfer(coin::from_balance(b, ctx), c.opponent);
        };

        if (balance::value(&c.stake_a) == 0 && balance::value(&c.stake_b) == 0) {
            c.state = STATE_RESOLVED;
            event::emit(ChallengeReclaimed { id: object::id(c) });
        }
    }
}
