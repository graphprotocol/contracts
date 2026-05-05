# maxSecondsPerCollection: Cap, Not Deadline

## Problem

`_requireValidCollect` treated `maxSecondsPerCollection` as a hard deadline:

```solidity
require(
    _collectionSeconds <= _agreement.maxSecondsPerCollection,
    RecurringCollectorCollectionTooLate(...)
);
uint256 maxTokens = _agreement.maxOngoingTokensPerSecond * _collectionSeconds;
```

If the indexer collects even 1 second past `maxSecondsPerCollection`, the transaction reverts and the agreement becomes permanently stuck. The only recovery was a zero-token collect that bypasses temporal validation entirely (since `_requireValidCollect` was inside `if (tokens != 0)`).

## Fix

Cap `collectionSeconds` at `maxSecondsPerCollection` in `_getCollectionInfo`, so all callers receive consistent capped seconds:

```solidity
uint256 elapsed = collectionEnd - collectionStart;
return (true, Math.min(elapsed, uint256(_agreement.maxSecondsPerCollection)), ...);
```

The payer's per-collection exposure is still bounded by `maxOngoingTokensPerSecond * maxSecondsPerCollection`. The indexer can collect after the window closes, but the token cap is the same as if they had collected exactly at the deadline.

## Token calculation is two-layer capping

Tokens collected are the minimum of two independent upper bounds:

1. **Data service request** — `IndexingAgreement._tokensToCollect` computes `collectionSeconds * (tokensPerSecond + tokensPerEntityPerSecond * entities)`. This is the data service's claim of what is owed, not a guaranteed payout.

2. **RCA payer cap** — `RecurringCollector._requireValidCollect` computes `maxOngoingTokensPerSecond * collectionSeconds` (plus `maxInitialTokens` on first collection) and returns `min(requested, cap)`.

Neither layer guarantees the amount — both are upper bounds. The actual payout is the minimum of the two, and may be further limited by available escrow balance.

## Why this is correct

1. **`_getMaxNextClaim` already caps.** The view function (used by escrow to compute worst-case exposure) clamps `windowSeconds` at `maxSecondsPerCollection` rather than returning 0. The mutation function should be consistent.

2. **`collectionSeconds` is derived from on-chain state**, not caller-supplied. The indexer's only leverage is _when_ they call. Capping means they can't extract more by waiting longer.

3. **No stuck agreements.** A missed window no longer requires cancellation or a zero-token hack to recover.

4. **`minSecondsPerCollection` is unaffected.** If elapsed time exceeds `maxSecondsPerCollection`, it trivially exceeds `minSecondsPerCollection` (since `max > min` is enforced at accept time).

5. **Initial tokens preserved.** `maxInitialTokens` is added on top of the capped ongoing amount on first collection. With a hard deadline, a late first collection reverts and the indexer loses both the initial bonus and the ongoing amount — misaligning incentives. With a cap, the initial bonus is always available.

6. **Late collection loses unclaimed seconds, not ability to collect.** After a capped collection, `lastCollectionAt` resets to `block.timestamp`, not `lastCollectionAt + maxSecondsPerCollection`. The indexer permanently loses tokens for the gap beyond the cap. This incentivizes timely collection without the cliff-edge of a hard revert.

## Zero-token temporal validation enforced

`_requireValidCollect` was previously inside `if (tokens != 0)`, allowing zero-token collections to update `lastCollectionAt` without temporal checks. With the cap in place there is no legitimate bypass scenario, so temporal validation now runs unconditionally.

This makes `lastCollectionAt` trustworthy as a liveness signal — it can only advance through temporally validated collections.

## Zero-POI special case removed

The old code special-cased `entities == 0 && poi == bytes32(0)` to force `tokens = 0`, bypassing `_tokensToCollect` and RC temporal validation. This existed as a reset mechanism for stuck agreements. With the cap fix, there are no stuck agreements, so the special case is removed.

Every collection now goes through `_tokensToCollect` and RC validation uniformly. Every POI is disputable — no exception is made for zero POI. (The Dispute Manager does not reject disputes for zero POI, so this is consistent end-to-end.)

## Contrast with indexing rewards

Indexing rewards require a zero-POI "heartbeat" to keep allocations alive because reward rates change per epoch and snapshots are influenced by other participants' activity. That reset mechanism exists because the system is inherently snapshot-driven.

RCA indexing fees have no snapshots. The rate (`tokensPerSecond`, `tokensPerEntityPerSecond`) is fixed at agreement accept/update time. No external state changes the per-second rate between collections. Capping is strictly correct — there is no reason to penalize a late collection beyond limiting it to `maxSecondsPerCollection` worth of tokens.
