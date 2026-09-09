# IssuanceAllocator.sol — pending updates

Tracking pending edits noted but deferred to avoid touching contract source until the next maintenance window.

## NatSpec drift after the Self-Minting Accumulation fix

PR #1334 made `_advanceSelfMintingBlock` accumulate `selfMintingOffset` unconditionally and collapsed `_distributeIssuance` into a single `_distributePendingIssuance` path. Two docstrings still describe the pre-fix behaviour:

- `_advanceSelfMintingBlock` (~L364–371): drop the "When paused, accumulates…" framing. Lead with the unconditional invariant; keep the pause case as the state where accumulation persists past the transaction.
- `distributeIssuance` "Pause behavior" block (~L346–351): drop the "Normal distribution if no accumulated self-minting, otherwise retroactive" split. Every unpaused distribution flows through `_distributePendingIssuance` using current rates over the undistributed range with `selfMintingOffset` as the budget bound.

## Duplicate `_advanceSelfMintingBlock` call in `_distributeIssuance`

`_distributeIssuance` (~L417) and `_distributePendingIssuance` (~L453) both call `_advanceSelfMintingBlock()`. Second call is a no-op in the steady-state path but still costs a function-call + SLOAD + compare. Drop the call in `_distributeIssuance` or split `_distributePendingIssuance`.
