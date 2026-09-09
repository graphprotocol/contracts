# Rewards Behaviour Changes

Functional summary of how reward behaviour changed between the Horizon mainnet baseline and the current issuance upgrade.

## Activation Overview

Changes fall into two categories:

- **Automatic on upgrade:** New logic that activates immediately when the upgraded contracts are deployed behind their proxies. No governance action required. These include: zero-signal detection, zero-allocated-tokens reclaim, POI presentation paths (claim/reclaim/defer), allocation resize staleness check, allocation close reclaim, and the `POIPresented` event.

- **Governance-gated:** Features that require explicit governance transactions after upgrade. In the abstract, until configured the system preserves legacy behaviour (rewards are dropped, not reclaimed). These include: setting the issuance allocator, configuring reclaim addresses (per-condition and default), setting the eligibility oracle, and changing the minimum subgraph signal threshold.

**What this deployment configures.** The governance batches executed alongside this upgrade turn several of the gated features on immediately, so their legacy behaviour does _not_ persist:

- **Issuance allocator — set.** The RewardsManager self-mints 100% of the rate (120.73 GRT/block); the RecurringAgreementManager gets 0 issuance (DIPs dormant at launch). Effective issuance rate is unchanged from before the upgrade.
- **Default reclaim address — set** (no per-condition addresses). Reclaiming is active for **every** condition via the catch-all fallback the moment the batch executes — previously-dropped rewards are now minted to the reclaim address.
- **Eligibility oracle — wired, then enabled.** The oracle is set on the RewardsManager (and RecurringAgreementManager), and a subsequent governance transaction in the plan sets the oracle's validation flag to true; both switches are required before `INDEXER_INELIGIBLE` denials can occur.
- **Minimum subgraph signal — unchanged.** The threshold is not modified.

The per-feature `Activates:` notes below reflect this deployment's configuration, not just the abstract gating.

## Issuance Rate

**Before:** A single `issuancePerBlock` storage variable, set by governance via `setIssuancePerBlock()`, determined all reward issuance.

**After:** An optional `issuanceAllocator` contract can be set by governance. When set, the effective issuance rate comes from the allocator (which can distribute issuance across multiple targets). When unset, the legacy `issuancePerBlock` value is used as a fallback. The allocator calls `beforeIssuanceAllocationChange()` on the RewardsManager before changing rates, ensuring accumulators are snapshotted first.

**Activates:** Governance-gated — requires `setIssuanceAllocator()`. Until called, the legacy `issuancePerBlock` value continues to apply.

## Reward Conditions

A new `RewardsCondition` library defines typed `bytes32` identifiers for every situation where rewards cannot be distributed normally:

| Condition              | Trigger                                              |
| ---------------------- | ---------------------------------------------------- |
| `NO_SIGNAL`            | Zero total curation signal globally                  |
| `SUBGRAPH_DENIED`      | Subgraph is on the denylist                          |
| `BELOW_MINIMUM_SIGNAL` | Subgraph signal below `minimumSubgraphSignal`        |
| `NO_ALLOCATED_TOKENS`  | Subgraph has signal but zero allocated tokens        |
| `INDEXER_INELIGIBLE`   | Indexer fails eligibility oracle check at claim time |
| `STALE_POI`            | POI presented after staleness deadline               |
| `ZERO_POI`             | POI is `bytes32(0)`                                  |
| `ALLOCATION_TOO_YOUNG` | Allocation created in the current epoch              |
| `CLOSE_ALLOCATION`     | Allocation being closed with uncollected rewards     |

**Activates:** Automatic on upgrade — the library and all condition checks are available immediately once the upgraded contracts are deployed.

## Reclaim System

**Before:** When rewards could not be distributed (denied subgraph, below-signal subgraph, stale POI, etc.), the tokens were silently lost -- never minted to anyone.

**After:** Undistributable rewards are _reclaimed_ by minting them to a configurable address. Governance can set a per-condition address via `setReclaimAddress(condition, address)` and a catch-all fallback via `setDefaultReclaimAddress(address)`. If neither is configured for a given condition, rewards are still not minted (preserving the old drop behaviour). Every reclaim emits a `RewardsReclaimed` event with the condition, amount, indexer, allocation, and subgraph.

**Activates:** Governance-gated — requires `setReclaimAddress()` and/or `setDefaultReclaimAddress()`. This deployment configures the **default** reclaim address (no per-condition addresses), so reclaiming is active for **every** condition via the catch-all fallback from the moment the batch executes: rewards that were previously dropped are now minted to the reclaim address.

## Zero Global Signal

**Before:** Issuance during periods with zero total curation signal was silently lost.

**After:** Detected in `updateAccRewardsPerSignal()` and reclaimed as `NO_SIGNAL`.

**Activates:** Automatic on upgrade — detection is built into the accumulator update. Reclaim requires a configured address for `NO_SIGNAL`, which this deployment supplies via the default reclaim address, so zero-signal issuance is reclaimed (minted) rather than dropped.

## Subgraph-Level Denial

**Before:** Denial was a binary gate checked only at `takeRewards()` time. When a subgraph was denied, `takeRewards()` returned 0 and emitted `RewardsDenied`. The calling AllocationManager still advanced the allocation's reward snapshot, permanently dropping those rewards.

**After:** Denial is handled at two levels:

- **RewardsManager (accumulator level):** When `onSubgraphSignalUpdate` or `onSubgraphAllocationUpdate` is called for a denied subgraph, `accRewardsForSubgraph` and `accRewardsPerAllocatedToken` freeze (stop increasing). New rewards accruing during the denial period are reclaimed immediately rather than accumulated. `setDenied()` now snapshots accumulators before changing denial state so the boundary is clean.

- **AllocationManager (claim level):** POI presentation for a denied subgraph is _deferred_ -- returns 0 **without advancing the allocation's snapshot**. This preserves uncollected pre-denial rewards. When the subgraph is later un-denied, those preserved rewards become claimable again.

**Activates:** Automatic on upgrade — the accumulator-level freeze and claim-level deferral apply immediately. Denial state itself is set via `setDenied()` (Governor or SubgraphAvailabilityOracle).

## Below-Minimum Signal

**Before:** `getAccRewardsForSubgraph()` silently excluded rewards for subgraphs below `minimumSubgraphSignal`. Those rewards were lost.

**After:** The same exclusion occurs, but excluded rewards are reclaimed to the `BELOW_MINIMUM_SIGNAL` address instead of being lost. Changes to `minimumSubgraphSignal` apply retroactively to all pending rewards at the next accumulator update, so governance should call `onSubgraphSignalUpdate()` on affected subgraphs before changing the threshold.

**Activates:** Automatic on upgrade for the reclaim path. Threshold changes via `setMinimumSubgraphSignal()` are retroactive — governance should call `onSubgraphSignalUpdate()` on affected subgraphs before changing the threshold.

## Zero Allocated Tokens

**Before:** When a subgraph had signal but no allocations, `getAccRewardsPerAllocatedToken()` returned 0 for per-token rewards. The subgraph-level accumulator still grew, but the rewards were stranded -- distributable to no one.

**After:** Detected as `NO_ALLOCATED_TOKENS` and reclaimed. When allocations resume, `accRewardsPerAllocatedToken` resumes from its stored value rather than resetting to zero.

**Activates:** Automatic on upgrade — detection is built into the accumulator update.

## Indexer Eligibility

**Before:** No per-indexer eligibility checks existed.

**After:** An optional `rewardsEligibilityOracle` can be set by governance. When set, the eligibility check runs at claim time — but **only on the claim path** (`takeRewards()`, condition `NONE`): a valid, reward-bearing POI that is not stale, non-zero, old enough, and on a non-denied subgraph. Behaviour when the indexer is ineligible depends on the `revertOnIneligible` flag:

- **`revertOnIneligible = true` (this deployment):** the POI presentation **reverts** (`"Indexer not eligible for rewards"`). Rewards are neither minted nor reclaimed — they stay pending and become collectable if the indexer regains eligibility before the allocation goes stale.
- **`revertOnIneligible = false`:** rewards are denied (emitting `RewardsDeniedDueToEligibility`) and reclaimed to the `INDEXER_INELIGIBLE` address (or the default reclaim address) — permanently forfeited.

Subgraph denial takes precedence: if a subgraph is denied, eligibility is not checked.

Because the check guards only the claim path, an ineligible indexer is **never locked out of the allocation**. A **zero POI** (`ZERO_POI`), a stale allocation (`STALE_POI`), and closing via `stopService` (`CLOSE_ALLOCATION`) all take reclaim/defer paths that skip the eligibility check and succeed — forfeiting the affected rewards to the reclaim address rather than reverting (and a zero POI still resets the staleness clock, keeping the allocation alive). Under `revertOnIneligible = true`, the only action ineligibility blocks is **collecting rewards via a valid POI**.

**Activates:** Governance-gated by **two** switches: `setRewardsEligibilityOracle()` on the RewardsManager, and `setEligibilityValidation(true)` on the oracle itself (it ships with validation disabled, so `isEligible` returns true for everyone until enabled). This deployment does both — the oracle is wired at upgrade and validation is enabled by a subsequent governance transaction in the plan — so eligibility enforcement becomes active. With `revertOnIneligible = true` (this deployment) that enforcement is a **revert** on the claim path, not an `INDEXER_INELIGIBLE` reclaim (see above). Note the oracle also fail-opens (returns eligible) if it receives no updates within its configured timeout.

## POI Presentation (AllocationManager)

**Before:** A single conditional expression decided whether `takeRewards()` was called. If any condition failed (stale, zero POI, too young, altruistic), rewards were set to 0. The allocation's reward snapshot always advanced and pending rewards were always cleared, permanently dropping any undistributable rewards.

**After:** Three distinct paths based on the determined condition:

1. **Claim** (`NONE`): `takeRewards()` mints tokens, distributed to indexer and delegators. Snapshot advances.
2. **Reclaim** (`STALE_POI`, `ZERO_POI`): `reclaimRewards()` mints tokens to the reclaim address. Snapshot advances and pending rewards are cleared.
3. **Defer** (`ALLOCATION_TOO_YOUNG`, `SUBGRAPH_DENIED`): Returns 0 **without advancing the snapshot or clearing pending rewards**. Rewards are preserved for later collection. Accumulators are still updated via `onSubgraphAllocationUpdate()` to keep reclaim tracking current.

The POI presentation timestamp is now recorded immediately on entry (before condition evaluation), so the staleness clock resets regardless of reward outcome. Over-delegation force-close is skipped on the deferred path to avoid closing allocations with preserved uncollected rewards.

**Activates:** Automatic on upgrade — the three-path logic applies to all POI presentations immediately.

## Allocation Resize

**Before:** Resizing always accumulated pending rewards for the delta period, regardless of allocation staleness.

**After:** If the allocation is stale at resize time, pending rewards are reclaimed as `STALE_POI` and cleared. This prevents stale allocations from silently accumulating pending rewards through repeated resizes.

**Activates:** Automatic on upgrade — applies to all resize operations immediately.

## Allocation Close

**Before:** Closing an allocation advanced the snapshot and closed it. Any uncollected rewards were permanently lost.

**After:** Before closing, `reclaimRewards(CLOSE_ALLOCATION, allocationId)` is called to mint uncollected rewards to the reclaim address.

**Activates:** Automatic on upgrade — applies to all close operations immediately.

## Observability

A new `POIPresented` event is emitted on every POI presentation, including the determined `condition` as a `bytes32` field. This provides off-chain visibility into why a given presentation did or did not result in rewards, which was previously invisible.

**Activates:** Automatic on upgrade — emitted on every POI presentation immediately.

## View Functions

Several view functions were added or changed to expose the new reward state.

### Accumulator Views Freeze for Non-Claimable Subgraphs

The existing accumulator view functions now exclude rewards for subgraphs that are not claimable (denied, below minimum signal, or with zero allocated tokens). Previously these accumulators always grew; callers reading them as continuously-increasing counters need to account for the new freeze behaviour.

**`getAccRewardsForSubgraph()`** — Previously always returned a growing value regardless of subgraph state. Now returns a frozen value when the subgraph is not claimable: the internal helper `_getSubgraphRewardsState()` determines a `RewardsCondition`, and when the condition is anything other than `NONE`, new rewards are excluded from the returned total. The accumulator resumes growing when the subgraph becomes claimable again.

**`getAccRewardsPerAllocatedToken()`** — Derives from `getAccRewardsForSubgraph()`, so it inherits the freeze. When the subgraph is not claimable, new per-token rewards are zero because the subgraph-level delta is zero. At snapshot points the implementation zeroes `undistributedRewards` and reclaims them instead of adding them to `accRewardsPerAllocatedToken`.

**`getRewards()`** — Returns the claimable reward estimate for an allocation. Because it reads `getAccRewardsPerAllocatedToken()`, it now returns a frozen value for allocations on non-claimable subgraphs. Pre-existing `accRewardsPending` from prior resizes is still included. Note: indexer eligibility is _not_ checked here (only at `takeRewards()` time), so the view does not reflect eligibility-based denial.

**`getNewRewardsPerSignal()`** — No visible change in return value. Internally it now separates claimable from unclaimable issuance (zero-signal periods), but the public view still returns only the claimable portion. The unclaimable portion is reclaimed as `NO_SIGNAL` at the next `updateAccRewardsPerSignal()` call.

### New Getters on IRewardsManager

| Function                            | Returns                           | Purpose                                                                                                                                                                                    |
| ----------------------------------- | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `getIssuanceAllocator()`            | `IIssuanceAllocationDistribution` | Current allocator contract (zero if unset)                                                                                                                                                 |
| `getReclaimAddress(bytes32 reason)` | `address`                         | Per-condition reclaim address (zero if unconfigured)                                                                                                                                       |
| `getDefaultReclaimAddress()`        | `address`                         | Fallback reclaim address                                                                                                                                                                   |
| `getRewardsEligibilityOracle()`     | `IRewardsEligibility`             | Current eligibility oracle (zero if unset)                                                                                                                                                 |
| `getAllocatedIssuancePerBlock()`    | `uint256`                         | Effective issuance rate — returns the allocator rate when set, otherwise falls back to storage. Replaces the legacy `getRewardsIssuancePerBlock()` for callers that need the protocol rate |
| `getRawIssuancePerBlock()`          | `uint256`                         | Raw storage value, ignoring the allocator. Useful for debugging allocator configuration                                                                                                    |

### Changed Return Semantics

**`getAllocationData()`** (IRewardsIssuer, implemented by SubgraphService) now returns a sixth value, `accRewardsPending`, representing accumulated rewards from allocation resizing that have not yet been claimed. Callers that destructure the return tuple need updating.

**`IAllocation.State`** struct adds two fields: `accRewardsPending` (pending rewards from resize) and `createdAtEpoch` (epoch when the allocation was created). Both affect the return value of `getAllocation()`.

## Provenance

Merge commits into `main` that introduced the changes described above, in chronological order.

| Date       | Merge       | PR    | Scope                                                                                                                                                                                     |
| ---------- | ----------- | ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2025-12-16 | `ff2f00a62` | #1265 | Eligibility oracle audit doc fixes (TRST-L-1, TRST-L-2)                                                                                                                                   |
| 2025-12-16 | `48be37a20` | #1267 | Issuance allocator audit fix — default allocation, `setReclaimAddress`                                                                                                                    |
| 2025-12-31 | `89f1321c4` | #1272 | Issuance allocator audit fix v3 — forced reclaim, PPM-to-absolute migration                                                                                                               |
| 2026-01-08 | `3d274a4f1` | #1255 | Issuance baseline — RewardsManager extensions, eligibility interface, test suites                                                                                                         |
| 2026-01-08 | `363924149` | #1256 | Rewards Eligibility Oracle — full oracle implementation                                                                                                                                   |
| 2026-01-08 | `cdef9b5fd` | #1257 | Issuance Allocator — full allocator, RewardsReclaim library, allocation close reclaim                                                                                                     |
| 2026-02-17 | `ada315500` | #1279 | Rewards reclaiming (audited) — RewardsCondition rename, `setDefaultReclaimAddress`, subgraph denial accumulator handling, zero-signal reclaim, POI three-path logic, `POIPresented` event |
| 2026-02-19 | `127b7ef6f` | #1280 | Issuance umbrella merge — all prior work plus stale-allocation-resize reclaim (TRST-R-1)                                                                                                  |
