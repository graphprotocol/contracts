# TRST-CL-2: IssuanceAllocator may skip minting due to hypothetical governance action

- **Category:** Logical flaws
- **Source:** IssuanceAllocator.sol
- **Status:** Fixed

## Description

The `_advanceSelfMintingBlock()` implementation optimizes the minting happy-path, and if there is no accumulating minting quota and the contract isn't paused, it does not increment the allocator. This is generally correct because under the presumed `_distributeIssuance()` call path, the happy path would lead to minting through `_performNormalDistribution()`, so accumulator should not be touched. However, there are hypothetical paths to the advance logic through the overloaded `distributePendingIssuance()`. In case these are used and the conditions for happy-path are met, the offset will not be updated, yet `_performNormalDistribution()` will not be called as part of the flow, causing under-minting of GRT.

The scenario is considered pathological because the governance-controlled distribution functions are unnecessary in the happy path, since `distributeIssuance()` achieves the same, and the contracts are past any sort of recovery mode at that point.

## Mitigation Review

The implementation has been simplified: the optimized path no longer exists and the accumulator invariant always holds.

---
