# RecurringAgreementManager

RCA-based payments require escrow pre-deposits — the payer must deposit enough tokens to cover the maximum that could be collected in the next collection window. RecurringAgreementManager automates this for protocol-escrowed agreements by receiving minted GRT from IssuanceAllocator and maintaining escrow balances sufficient to cover worst-case collection amounts.

It implements three interfaces:

- **`IIssuanceTarget`** — receives minted GRT from IssuanceAllocator
- **`IContractApprover`** — authorizes RCA acceptance and updates via callback (replaces ECDSA signature)
- **`IRecurringAgreementManager`** — core escrow management functions

## Escrow Structure

One escrow account per (RecurringAgreementManager, RecurringCollector, service provider) tuple covers **all** managed RCAs for that service provider. Multiple agreements for the same provider share a single escrow balance:

```
sum(maxNextClaim + pendingUpdateMaxNextClaim for all active agreements for that provider) <= PaymentsEscrow.escrowAccounts[RecurringAgreementManager][RecurringCollector][provider]
```

Deposits never revert — `_escrowMinMax` degrades the mode when balance is insufficient, ensuring the deposit amount is always affordable. The `getEscrowAccount` view exposes the underlying escrow account for monitoring.

## Hash Authorization

The `authorizedHashes` mapping stores `hash → agreementId` rather than `hash → bool`. Hashes are automatically invalidated when agreements are deleted, preventing reuse without explicit cleanup.

## Max Next Claim

For accepted agreements, delegated to `RecurringCollector.getMaxNextClaim(agreementId)` as the single source of truth. For pre-accepted offers, a conservative estimate calculated at offer time:

```
maxNextClaim = maxOngoingTokensPerSecond * maxSecondsPerCollection + maxInitialTokens
```

| Agreement State             | maxNextClaim                                                   |
| --------------------------- | -------------------------------------------------------------- |
| NotAccepted (pre-offered)   | Stored estimate from `offerAgreement`                          |
| NotAccepted (past deadline) | 0 (expired offer, removable)                                   |
| Accepted, never collected   | Calculated by RecurringCollector (includes initial + ongoing)  |
| Accepted, after collect     | Calculated by RecurringCollector (ongoing only)                |
| CanceledByPayer             | Calculated by RecurringCollector (window frozen at canceledAt) |
| CanceledByServiceProvider   | 0                                                              |
| Fully expired               | 0                                                              |

## Lifecycle

### Offer → Accept (two-step)

1. **Operator** calls `offerAgreement(rca)` — stores hash, calculates conservative maxNextClaim, deposits into escrow
2. **Service provider operator** calls `SubgraphService.acceptUnsignedIndexingAgreement(allocationId, rca)` — SubgraphService → RecurringCollector → `approveAgreement(hash)` callback to RecurringAgreementManager

During the pending update window, both current and pending maxNextClaim are escrowed simultaneously (conservative).

### Collect → Reconcile

Collection flows through `SubgraphService → RecurringCollector → PaymentsEscrow`. RecurringCollector then calls `IContractApprover.afterCollection` on the payer, which triggers automatic reconciliation and escrow top-up in the same transaction. Manual reconcile is still available as a fallback.

The manager exposes `reconcileAgreement` (gas-predictable, per-agreement). Batch convenience functions `reconcileBatch` (caller-selected list) and `reconcile(provider)` (iterates all agreements) are in the stateless `RecurringAgreementHelper` contract, which delegates each reconciliation back to the manager.

### Revoke / Cancel / Remove

- **`revokeOffer`** — withdraws an un-accepted offer
- **`cancelAgreement`** — for accepted agreements, routes cancellation through the data service then reconciles; idempotent for already-canceled agreements
- **`removeAgreement`** (permissionless) — cleans up agreements with maxNextClaim = 0

| State                     | Removable when                        |
| ------------------------- | ------------------------------------- |
| CanceledByServiceProvider | Immediately (maxNextClaim = 0)        |
| CanceledByPayer           | After collection window expires       |
| Accepted past endsAt      | After final collection window expires |
| NotAccepted (expired)     | After `rca.deadline` passes           |

## Escrow Modes

The configured `EscrowBasis` controls how aggressively escrow is pre-deposited. The setting is a **maximum aspiration** — the system automatically degrades when balance is insufficient. `beforeCollection` (JIT top-up) is always active regardless of setting, providing a safety net for any gap.

### Levels

```
enum EscrowBasis { JustInTime, OnDemand, Full }
```

Ordered low-to-high:

| Level          | min (deposit floor)                      | max (thaw ceiling) | Behavior                                           |
| -------------- | ---------------------------------------- | ------------------ | -------------------------------------------------- |
| Full (2)       | `sumMaxNextClaim[provider]` (sum of all) | `sumMaxNextClaim`  | Current default. Deposits worst-case for all RCAs. |
| OnDemand (1)   | 0                                        | `sumMaxNextClaim`  | No deposits, holds at sumMaxNextClaim level.       |
| JustInTime (0) | 0                                        | 0                  | Thaws everything, pure JIT.                        |

**Stability guarantee**: `min <= max` at every level. Deposit-then-immediate-reconcile at the same level never triggers a thaw.

### Min/Max Model

`_updateEscrow` uses two numbers from `_escrowMinMax` instead of a single `sumMaxNextClaim`:

- **min**: deposit floor — deposit if effective balance is below this
- **max**: thaw ceiling — thaw effective balance above this (never resetting an active thaw timer)

The split ensures smooth transitions between levels. When degradation occurs, min drops to 0 but max holds at `sumMaxNextClaim`, preventing oscillation.

### Automatic Degradation

The setting is a ceiling, not a mandate. When balance is insufficient, Full degrades to OnDemand:

| Configured | Can afford?    | Effective min     | Effective max     |
| ---------- | -------------- | ----------------- | ----------------- |
| Full       | Yes            | `sumMaxNextClaim` | `sumMaxNextClaim` |
| Full       | No (→OnDemand) | 0                 | `sumMaxNextClaim` |
| OnDemand   | Always         | 0                 | `sumMaxNextClaim` |
| JustInTime | Always         | 0                 | 0                 |

Degradation trigger:

- **Full → OnDemand**: `totalEscrowDeficit >= available` (RAM's balance can't close the system-wide gap)

Key properties:

- Degradation never reaches JustInTime automatically — only explicit governor setting or enforced JIT thaws to zero
- JIT deposit is all-or-nothing: if `deficit < available` the full deficit is deposited, otherwise nothing is deposited

### `_updateEscrow` Flow

`_updateEscrow(collector, provider)` normalizes escrow state in four steps using (min, max) from `_escrowMinMax`:

1. **Adjust thaw target** — cancel/reduce unrealised thawing to keep effective balance >= min, or increase thawing toward max. Never resets the thaw timer (`evenIfTimerReset=false`).
2. **Withdraw completed thaw** — realised thawing is always withdrawn, even if within [min, max].
3. **Thaw excess** — if no thaw is active (possibly after a withdraw), start a new thaw for balance above max.
4. **Deposit deficit** — if no thaw is active, deposit to reach min.

Steps 3 and 4 are mutually exclusive (min <= max). The thaw timer is never reset: step 1 uses `evenIfTimerReset=false`, and steps 3/4 only run when `tokensThawing == 0`.

### Reconciliation

Per-agreement reconciliation (`reconcileAgreement`) re-reads agreement state from RecurringCollector and updates `sumMaxNextClaim`. Provider-level escrow rebalancing is O(1) via `updateEscrow(provider)`. Batch helpers `reconcileBatch` and `reconcile(provider)` live in the separate `RecurringAgreementHelper` contract — they are stateless wrappers that call `reconcileAgreement` in a loop.

### Global Tracking

| Storage field          | Type    | Updated at                                                                     |
| ---------------------- | ------- | ------------------------------------------------------------------------------ |
| `escrowBasis`          | enum    | `setEscrowBasis()` (also clears enforced JIT)                                  |
| `sumMaxNextClaimAll`   | uint256 | Every `sumMaxNextClaim[provider]` mutation                                     |
| `totalEscrowDeficit`   | uint256 | Every `sumMaxNextClaim[provider]` or `escrowSnap[provider]` mutation           |
| `totalAgreementCount`  | uint256 | `offerAgreement` (+1), `revokeOffer` (-1), `removeAgreement` (-1)              |
| `escrowSnap[provider]` | mapping | End of `_updateEscrow` via snapshot diff                                       |
| `enforcedJit`          | bool    | `beforeCollection` (trip), `_updateEscrow` (recover), `setEscrowBasis` (clear) |

**`totalEscrowDeficit`** is maintained incrementally as `Σ max(0, sumMaxNextClaim[p] - escrowSnap[p])` per provider. This correctly handles over-deposited providers: a provider with excess escrow cannot mask another provider's deficit. At each of 6 mutation points (offer, offerUpdate, revoke, remove, reconcile, setEscrowSnap), the provider's deficit is recomputed before and after the mutation.

Globals start at 0 and populate lazily through normal operations. This is safe because Full mode's per-provider logic uses `sumMaxNextClaim[provider]` directly (unaffected by globals), and degradation with `totalEscrowDeficit=0` means no degradation triggers (stays Full). Governor should run a reconciliation pass across providers before switching away from Full mode to populate globals.

### Enforced JIT

If `beforeCollection` can't fully deposit for a collection (`deficit >= available`), it deposits nothing and enforces JIT mode. While active, `_escrowMinMax` returns `(0, 0)` — JIT-only behavior — regardless of the configured `escrowBasis`. The configured basis is preserved and takes effect again on recovery.

**Trigger**: In `beforeCollection`, if `deficit >= available` (all-or-nothing: no partial deposits) and not already enforced:

- Set `enforcedJit = true`
- Emit `EnforcedJit($.escrowBasis)` (configured basis unchanged)

**Recovery**: In `_updateEscrow` (runs after every reconcile, collection, etc.), if enforced and `totalEscrowDeficit <= GRAPH_TOKEN.balanceOf(this)`:

- Clear `enforcedJit`
- Emit `EnforcedJitRecovered($.escrowBasis)`

Recovery uses `totalEscrowDeficit` — the sum of per-(collector, provider) deficits — rather than total sumMaxNextClaim. This correctly accounts for already-deposited escrow. During JIT mode, thaws complete and tokens return to RAM, naturally building toward recovery.

**Governor override**: `setEscrowBasis` always clears enforced JIT, regardless of recovery conditions.

### Upgrade Safety

Default storage value 0 maps to `JustInTime`, so `reinitializer(2)` sets `escrowBasis = Full` to preserve current behavior. The `initializeV2()` function handles this. `enforcedJit` defaults to `false` (0), which is correct — no enforcement on upgrade.

## Roles

- **GOVERNOR_ROLE**: Sets the issuance allocator reference, sets escrow basis
- **OPERATOR_ROLE**: Offers agreements/updates, revokes offers, cancels agreements
- **PAUSE_ROLE**: Pauses contract (reconcile/remove remain available)
- **Permissionless**: `reconcileAgreement`, `removeAgreement`, `updateEscrow`
- **RecurringAgreementHelper** (permissionless): `reconcile(provider)`, `reconcileBatch(ids[])`

## Deployment

Prerequisites: GraphToken, PaymentsEscrow, RecurringCollector, IssuanceAllocator deployed.

1. Deploy RecurringAgreementManager implementation (graphToken, paymentsEscrow, recurringCollector)
2. Deploy TransparentUpgradeableProxy with implementation and initialization data
3. Initialize with governor address
4. Grant `OPERATOR_ROLE` to the operator account
5. Configure IssuanceAllocator to allocate tokens to RecurringAgreementManager
