# RecurringAgreementManager

RCA-based payments require escrow pre-deposits — the payer must deposit enough tokens to cover the maximum that could be collected in the next collection window. RecurringAgreementManager automates this for protocol-escrowed agreements by receiving minted GRT from IssuanceAllocator and maintaining escrow balances sufficient to cover worst-case collection amounts.

It implements seven interfaces:

- **`IIssuanceTarget`** — receives minted GRT from IssuanceAllocator
- **`IAgreementOwner`** — authorizes RCA acceptance and updates via callback (replaces ECDSA signature)
- **`IRecurringAgreementManagement`** — agreement lifecycle: offer, update, revoke, cancel, remove, reconcile
- **`IRecurringEscrowManagement`** — escrow configuration: setEscrowBasis, setTempJit
- **`IProviderEligibilityManagement`** — eligibility oracle configuration: setProviderEligibilityOracle
- **`IRecurringAgreements`** — read-only queries: agreement info, escrow state, global tracking
- **`IProviderEligibility`** — delegates payment eligibility checks to an optional oracle

## Escrow Structure

One escrow account per (RecurringAgreementManager, collector, provider) tuple covers **all** managed RCAs for that (collector, provider) pair. Multiple agreements for the same pair share a single escrow balance:

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

1. **Agreement manager** calls `offerAgreement(rca, collector)` — stores hash, calculates conservative maxNextClaim, deposits into escrow
2. **Service provider operator** calls `SubgraphService.acceptUnsignedIndexingAgreement(allocationId, rca)` — SubgraphService → RecurringCollector → `approveAgreement(hash)` callback to RecurringAgreementManager

During the pending update window, both current and pending maxNextClaim are escrowed simultaneously (conservative).

### Collect → Reconcile

Collection flows through `SubgraphService → RecurringCollector → PaymentsEscrow`. RecurringCollector then calls `IAgreementOwner.afterCollection` on the payer, which triggers automatic reconciliation and escrow top-up in the same transaction. Manual reconcile is still available as a fallback.

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

| Level          | min (deposit floor) | max (thaw ceiling) | Behavior                                           |
| -------------- | ------------------- | ------------------ | -------------------------------------------------- |
| Full (2)       | `sumMaxNextClaim`   | `sumMaxNextClaim`  | Current default. Deposits worst-case for all RCAs. |
| OnDemand (1)   | 0                   | `sumMaxNextClaim`  | No deposits, holds at sumMaxNextClaim level.       |
| JustInTime (0) | 0                   | 0                  | Thaws everything, pure JIT.                        |

`sumMaxNextClaim` here means the per-(collector, provider) sum from storage.

**Stability guarantee**: `min <= max` at every level. Deposit-then-immediate-reconcile at the same level never triggers a thaw.

### Min/Max Model

`_updateEscrow` uses two numbers from `_escrowMinMax` instead of a single `sumMaxNextClaim`:

- **min**: deposit floor — deposit if effective balance is below this
- **max**: thaw ceiling — thaw effective balance above this (never resetting an active thaw timer)

The split ensures smooth transitions between levels. When degradation occurs, min drops to 0 but max holds at `sumMaxNextClaim`, preventing oscillation.

### Automatic Degradation

The setting is a ceiling, not a mandate. **Full → OnDemand** when `available <= totalEscrowDeficit` (RAM's balance can't close the system-wide gap): min drops to 0, max stays at `sumMaxNextClaim`. Degradation never reaches JustInTime automatically — only explicit operator setting or temp JIT.

### `_updateEscrow` Flow

`_updateEscrow(collector, provider)` normalizes escrow state in four steps using (min, max) from `_escrowMinMax`. Steps 3 and 4 are mutually exclusive (min <= max); the thaw timer is never reset.

1. **Adjust thaw target** — cancel/reduce thawing to keep min <= effective balance, or increase toward max (without timer reset)
2. **Withdraw completed thaw** — always withdrawn, even if within [min, max]
3. **Thaw excess** — if no thaw active, start new thaw for balance above max
4. **Deposit deficit** — if no thaw active, deposit to reach min

### Reconciliation

Per-agreement reconciliation (`reconcileAgreement`) re-reads agreement state from RecurringCollector and updates `sumMaxNextClaim`. Pair-level escrow rebalancing and cleanup is O(1) via `reconcileCollectorProvider(collector, provider)`. Batch helpers `reconcileBatch` and `reconcile(provider)` live in the separate `RecurringAgreementHelper` contract — they are stateless wrappers that call `reconcileAgreement` in a loop.

### Global Tracking

| Storage field         | Type    | Updated at                                                                  |
| --------------------- | ------- | --------------------------------------------------------------------------- |
| `escrowBasis`         | enum    | `setEscrowBasis()`                                                          |
| `sumMaxNextClaimAll`  | uint256 | Every `sumMaxNextClaim[c][p]` mutation                                      |
| `totalEscrowDeficit`  | uint256 | Every `sumMaxNextClaim[c][p]` or `escrowSnap[c][p]` mutation                |
| `totalAgreementCount` | uint256 | `offerAgreement` (+1), `revokeOffer` (-1), `removeAgreement` (-1)           |
| `escrowSnap[c][p]`    | mapping | End of `_updateEscrow` via snapshot diff                                    |
| `tempJit`             | bool    | `beforeCollection` (trip), `_updateEscrow` (recover), `setTempJit` (manual) |

**`totalEscrowDeficit`** is maintained incrementally as `Σ max(0, sumMaxNextClaim[c][p] - escrowSnap[c][p])` per (collector, provider). Over-deposited pairs cannot mask another pair's deficit. At each mutation point, the pair's deficit is recomputed before and after.

### Temp JIT

If `beforeCollection` can't fully deposit for a collection (`available <= deficit`), it deposits nothing and activates temporary JIT mode. While active, `_escrowMinMax` returns `(0, 0)` — JIT-only behavior — regardless of the configured `escrowBasis`. The configured basis is preserved and takes effect again on recovery.

**Trigger**: `beforeCollection` activates temp JIT when `available <= deficit` (all-or-nothing: no partial deposits).

**Recovery**: `_updateEscrow` clears temp JIT when `totalEscrowDeficit < available`. Recovery uses `totalEscrowDeficit` (sum of per-(collector, provider) deficits) rather than total sumMaxNextClaim, correctly accounting for already-deposited escrow. During JIT mode, thaws complete and tokens return to RAM, naturally building toward recovery.

**Operator override**: `setTempJit(bool)` allows direct control. `setEscrowBasis` does not affect `tempJit` — the two settings are independent.

### Upgrade Safety

Default storage value 0 maps to `JustInTime`, so `initialize()` sets `escrowBasis = Full` as the default. Future upgrades must set it explicitly via a reinitializer. `tempJit` defaults to `false` (0), which is correct — no temp JIT on fresh deployment.

## Roles

- **GOVERNOR_ROLE**: Sets issuance allocator, eligibility oracle; grants `DATA_SERVICE_ROLE`, `COLLECTOR_ROLE`, and other roles; admin of `OPERATOR_ROLE`
- **OPERATOR_ROLE**: Sets escrow basis and temp JIT; admin of `AGREEMENT_MANAGER_ROLE`
  - **AGREEMENT_MANAGER_ROLE**: Offers agreements/updates, revokes offers, cancels agreements
- **PAUSE_ROLE**: Pauses contract (reconcile/remove remain available)
- **Permissionless**: `reconcileAgreement`, `removeAgreement`, `reconcileCollectorProvider`
- **RecurringAgreementHelper** (permissionless): `reconcile(provider)`, `reconcileBatch(ids[])`

## Deployment

Prerequisites: GraphToken, PaymentsEscrow, RecurringCollector, IssuanceAllocator deployed.

1. Deploy RecurringAgreementManager implementation (graphToken, paymentsEscrow)
2. Deploy TransparentUpgradeableProxy with implementation and initialization data
3. Initialize with governor address
4. Grant `OPERATOR_ROLE` to the operator account
5. Operator grants `AGREEMENT_MANAGER_ROLE` to the agreement manager account
6. Configure IssuanceAllocator to allocate tokens to RecurringAgreementManager
