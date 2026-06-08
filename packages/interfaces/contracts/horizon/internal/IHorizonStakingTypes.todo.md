# IHorizonStakingTypes.sol — pending updates

Tracking pending edits noted but deferred to avoid touching contract source until the next maintenance window. When picking up, drop the corresponding entry below as part of the same commit.

## `LegacyAllocationState.Active` NatSpec drift

The enum docstring at L233 describes the `Active` state as `not Null && tokens > 0`, but the implementation in `_getLegacyAllocationState` (`packages/horizon/contracts/staking/HorizonStaking.sol:1190`) gates on `createdAtEpoch != 0 && closedAtEpoch == 0` — no `tokens > 0` check.

`createdAtEpoch` is set together with `indexer` at allocation creation, so `createdAtEpoch != 0` is equivalent to `not NULL`. The docstring's `tokens > 0` clause has no implementation counterpart.

Suggested replacement:

```solidity
 * - Null = indexer == address(0)
 * - Active = not Null && closedAtEpoch == 0
 * - Closed = not Null && closedAtEpoch != 0
```

Also tightens `Closed` away from the recursive `Active && closedAtEpoch != 0` framing, which becomes circular once `Active` is restated.

**Origin:** Inline review nits from Maikol on PR #1331 (2026-05-07, L233 & L234); PR was approved with these threads left open as non-blocking.
