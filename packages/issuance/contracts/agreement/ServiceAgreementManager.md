# ServiceAgreementManager

The ServiceAgreementManager is a smart contract that funds PaymentsEscrow deposits for Recurring Collection Agreements (RCAs) using tokens received from the IssuanceAllocator. It tracks the maximum possible next claim for each managed RCA and keeps the escrow balance for each indexer equal to the sum of those maximums.

## Overview

When the protocol needs to pay indexers via RCAs, someone must be the "payer" who deposits tokens into PaymentsEscrow. The ServiceAgreementManager fills this role for protocol-funded agreements: it receives minted GRT from IssuanceAllocator and uses it to maintain escrow balances sufficient to cover worst-case collection amounts.

### Problem

RCA-based payments require escrow pre-funding. The payer must deposit enough tokens to cover the maximum that could be collected in the next collection window. Without automation, this requires manual deposits and monitoring.

### Solution

ServiceAgreementManager automates this by:

1. Receiving issuance tokens (via `IIssuanceTarget`, like DirectAllocation)
2. Acting as the RCA payer (via `IContractApprover` callback)
3. Tracking per-agreement max-next-claim and funding escrow to cover totals

## Architecture

### Contract Interfaces

ServiceAgreementManager implements three interfaces:

| Interface                  | Purpose                                                                       |
| -------------------------- | ----------------------------------------------------------------------------- |
| `IIssuanceTarget`          | Receives minted GRT from IssuanceAllocator                                    |
| `IContractApprover`        | Authorizes RCA acceptance and updates via callback (replaces ECDSA signature) |
| `IServiceAgreementManager` | Core escrow management functions                                              |

### Escrow Structure

One escrow account per (ServiceAgreementManager, RecurringCollector, indexer) tuple covers **all** managed RCAs for that indexer. This means multiple agreements for the same indexer share a single escrow balance.

```
PaymentsEscrow.escrowAccounts[ServiceAgreementManager][RecurringCollector][indexer]
  >= sum(maxNextClaim + pendingUpdateMaxNextClaim for all active agreements for that indexer)
```

### Roles

- **GOVERNOR_ROLE**: Can set the issuance allocator reference (IIssuanceTarget requirement)
- **OPERATOR_ROLE**: Can offer agreements/updates, revoke offers, and cancel agreements
- **PAUSE_ROLE**: Can pause contract operations (inherited from BaseUpgradeable)
- **Permissionless**: `reconcile`, `reconcileAgreement`, `reconcileBatch`, `removeAgreement`, and `maintain` can be called by anyone

### Storage (ERC-7201)

```solidity
struct ServiceAgreementManagerStorage {
  mapping(bytes32 => bytes16) authorizedHashes; // Hash → agreementId (for IContractApprover callback)
  mapping(bytes16 => AgreementInfo) agreements; // Per-agreement tracking
  mapping(address => uint256) requiredEscrow; // Sum of maxNextClaims per indexer
  mapping(address => EnumerableSet.Bytes32Set) indexerAgreementIds; // Agreement set per indexer
  mapping(address => bool) thawing; // Thaw-in-progress flag per indexer
}
```

### Hash Authorization

The `authorizedHashes` mapping stores `hash → agreementId` rather than `hash → bool`. When `approveAgreement(hash)` is called, it checks both that the hash maps to a valid agreementId **and** that the corresponding agreement still exists. This means:

- Hashes are automatically invalidated when agreements are deleted (via `revokeOffer` or `removeAgreement`)
- No explicit hash cleanup is needed
- Each hash is tied to a specific agreement, preventing hash reuse across agreements

## Max Next Claim

The max-next-claim calculation is delegated to `RecurringCollector.getMaxNextClaim(agreementId)` for accepted agreements. This provides a single source of truth and avoids divergence between ServiceAgreementManager's estimate and the actual collection logic.

For **pre-accepted** (NotAccepted) agreements, ServiceAgreementManager uses a conservative estimate calculated at offer time:

```
maxNextClaim = maxOngoingTokensPerSecond * maxSecondsPerCollection + maxInitialTokens
```

### State-Dependent Results

| Agreement State             | maxNextClaim                                                   |
| --------------------------- | -------------------------------------------------------------- |
| NotAccepted (pre-offered)   | Uses stored estimate from `offerAgreement`                     |
| NotAccepted (past deadline) | 0 (expired offer, removable)                                   |
| Accepted, never collected   | Calculated by RecurringCollector (includes initial + ongoing)  |
| Accepted, after collect     | Calculated by RecurringCollector (ongoing only)                |
| CanceledByPayer             | Calculated by RecurringCollector (window frozen at canceledAt) |
| CanceledByServiceProvider   | 0                                                              |
| Fully expired               | 0                                                              |

## Lifecycle

### 1. Offer Agreement

```
Operator calls offerAgreement(rca)
```

- Validates `rca.payer == address(this)` (ServiceAgreementManager is the payer)
- Computes `agreementId` deterministically from RCA fields
- Calculates initial `maxNextClaim = maxOngoingTokensPerSecond * maxSecondsPerCollection + maxInitialTokens`
- Stores the agreement hash for the `IContractApprover` callback (hash → agreementId)
- Cancels any in-progress thaw for this indexer (new agreement needs funded escrow)
- Funds the escrow (deposits deficit from available token balance)

### 2. Accept Agreement

```
Indexer operator calls SubgraphService.acceptUnsignedIndexingAgreement(allocationId, rca)
```

- SubgraphService calls `RecurringCollector.acceptUnsigned(rca)`
- RecurringCollector calls `agreementManager.approveAgreement(hash)` to verify (via `rca.payer`)
- ServiceAgreementManager confirms (returns magic value) because the hash was stored in step 1
- Agreement is now accepted in RecurringCollector

**Ordering**: `offerAgreement` **must** be called before `acceptUnsignedIndexingAgreement`. The two-step flow ensures escrow is funded before the agreement becomes active.

### 3. Offer Agreement Update

```
Operator calls offerAgreementUpdate(rcau)
```

- Validates the agreement exists (was previously offered)
- Calculates `pendingMaxNextClaim = maxOngoingTokensPerSecond * maxSecondsPerCollection + maxInitialTokens` from the RCAU parameters
- If replacing a previous pending update, removes the old pending from `requiredEscrow`
- Stores the RCAU hash for the `IContractApprover` callback (hash → agreementId)
- Adds `pendingMaxNextClaim` to `requiredEscrow` (conservative: both current and pending are funded)
- Funds the escrow

### 4. Accept Agreement Update

```
Indexer operator calls SubgraphService.updateUnsignedIndexingAgreement(indexer, rcau)
```

- SubgraphService calls `RecurringCollector.updateUnsigned(rcau)`
- RecurringCollector calls `agreementManager.approveAgreement(hash)` to verify
- ServiceAgreementManager confirms because the hash was stored in step 3
- Agreement terms are updated in RecurringCollector

**After acceptance**: call `reconcile` to clear the pending update and recalculate the escrow requirement based on the new terms.

### 5. Collect

```
SubgraphService.collect() -> RecurringCollector -> PaymentsEscrow.collect()
```

- Escrow balance decreases by `tokensCollected`
- No callback to ServiceAgreementManager (PaymentsEscrow has no post-collect hook)
- After collection, `reconcile` should be called to recalculate and top up

### 6. Reconcile

```
Anyone calls reconcileAgreement(agreementId), reconcileBatch(ids), or reconcile(indexer)
```

**reconcileAgreement** (primary — gas-predictable, per-agreement):

- Re-reads agreement state from RecurringCollector
- Clears pending updates if they have been applied on-chain (checks `updateNonce`)
- Recalculates `maxNextClaim` via `RecurringCollector.getMaxNextClaim(agreementId)`
- Updates `requiredEscrow` (sum adjustment)
- Deposits deficit from available token balance
- Skips NotAccepted agreements (preserves pre-offered estimate)

**reconcileBatch** (controlled batching):

- Two-pass design: first reconciles all agreements, then funds each unique indexer once
- Reconciles a caller-selected list of agreement IDs in a single transaction
- Skips non-existent agreements silently

**reconcile(indexer)** (convenience — O(n) gas):

- Iterates all tracked agreements for the indexer
- May hit gas limits with many agreements; prefer `reconcileAgreement` or `reconcileBatch`

Reconciliation is important after:

- A collection occurs (reduces the required escrow after initial tokens are claimed)
- An agreement is canceled
- An RCAU (agreement update) is applied (clears pending update, recalculates from new terms)
- Time passes and the remaining collection window shrinks

### 7. Revoke Offer

```
Operator calls revokeOffer(agreementId)
```

- Only for un-accepted agreements (NotAccepted state in RecurringCollector)
- Removes the agreement from tracking and reduces `requiredEscrow`
- Also clears any pending update for the agreement
- Authorized hashes are automatically invalidated (hash → deleted agreementId)

Use when an offer should be withdrawn before the indexer accepts it.

### 8. Cancel Agreement

```
Operator calls cancelAgreement(agreementId)
```

State-dependent behavior:

| Agreement State           | Behavior                                                   |
| ------------------------- | ---------------------------------------------------------- |
| NotAccepted               | Reverts with `AgreementNotAccepted` (use `revokeOffer`)    |
| Accepted                  | Cancels via data service, then reconciles and funds escrow |
| CanceledByPayer           | Idempotent: reconciles and funds escrow (already canceled) |
| CanceledByServiceProvider | Idempotent: reconciles and funds escrow (already canceled) |

For Accepted agreements:

- Validates the data service has deployed code (`InvalidDataService` if not)
- Routes cancellation through `ISubgraphService(dataService).cancelIndexingAgreementByPayer(agreementId)`
- The data service's `cancelByPayer` checks that `msg.sender == payer` (ServiceAgreementManager)
- After cancellation, automatically reconciles and funds escrow
- Once the collection window closes, call `removeAgreement` to clean up

For already-canceled agreements, calling `cancelAgreement` is idempotent — it skips the data service call and just reconciles/funds, which is useful for updating escrow tracking.

### 9. Remove Agreement

```
Anyone calls removeAgreement(agreementId)
```

- Only succeeds when the current max next claim is 0 (no more claims possible)
- For accepted agreements: delegates to `RecurringCollector.getMaxNextClaim(agreementId)`
- For NotAccepted agreements: removable only if the offer deadline has passed
- Removes tracking data (including any pending update) and reduces `requiredEscrow`
- Permissionless: anyone can remove expired agreements to keep state clean

This covers:

| State                     | Removable when                        |
| ------------------------- | ------------------------------------- |
| CanceledByServiceProvider | Immediately (maxNextClaim = 0)        |
| CanceledByPayer           | After collection window expires       |
| Accepted past endsAt      | After final collection window expires |
| NotAccepted (expired)     | After `rca.deadline` passes           |

### 10. Maintain (Thaw/Withdraw)

```
Anyone calls maintain(indexer)
```

Two-phase operation for recovering excess escrow when an indexer has no remaining agreements:

**Phase 1 — Thaw**: If there is available balance in PaymentsEscrow, initiates a thaw for the full amount. Sets the `thawing` flag.

**Phase 2 — Withdraw**: If a previous thaw has completed (thawing period elapsed), withdraws tokens back to ServiceAgreementManager. Then checks for any remaining balance and starts a new thaw if needed.

Guards:

- Reverts if the indexer still has tracked agreements (`StillHasAgreements`)
- If a thaw is in progress but not yet complete, returns early (no-op)
- If a new agreement is offered for an indexer during thawing, `offerAgreement` calls `cancelThaw` and resets the flag

## Post-Collection Economics

After a collection of `tokensCollected` from agreement A for indexer I:

| Scenario           | Required After Reconcile    | Balance After Collect      | Deficit to Fund                    |
| ------------------ | --------------------------- | -------------------------- | ---------------------------------- |
| First collection   | Required - maxInitialTokens | Required - tokensCollected | tokensCollected - maxInitialTokens |
| Ongoing collection | Required (unchanged)        | Required - tokensCollected | tokensCollected                    |

For ongoing collections, the deficit equals `tokensCollected`. The issuance rate should be calibrated to generate enough tokens between collections to cover this.

## Funding Behavior

The `_fundEscrow` function deposits the minimum of the deficit and the available token balance:

```
toDeposit = min(deficit, GRAPH_TOKEN.balanceOf(address(this)))
```

This means:

- **Never reverts** due to insufficient tokens
- Deposits what's available, even if it's less than the full deficit
- `getDeficit(indexer)` view function exposes shortfall for monitoring
- Issuance from IssuanceAllocator should keep the balance topped up between collections

## Security Considerations

- **Operator trust**: Only `OPERATOR_ROLE` can offer agreements/updates, revoke offers, and cancel agreements — controlling which RCAs the contract pays for
- **Permissionless reconcile/remove/maintain**: Anyone can call these to ensure the system stays current (no griefing risk since they only improve state accuracy or recover excess escrow)
- **Pre-offer ordering**: The hash must be stored before acceptance, preventing unauthorized agreements
- **Hash-to-agreement binding**: Authorized hashes map to specific agreementIds and are automatically invalidated when the agreement is deleted
- **Conservative estimates**: Pre-offered maxNextClaim overestimates (includes both initial and ongoing), ensuring sufficient funding
- **Pending update double-funding**: Both current and pending maxNextClaim are funded simultaneously, ensuring coverage regardless of which terms are active
- **Thaw guard**: The `thawing` flag prevents initiating a new thaw for less than an in-progress thaw. New agreements cancel any in-progress thaw via `cancelThaw`
- **Expired offer handling**: Offers that pass their RCA deadline without acceptance become removable, preventing permanent escrow lock-up
- **Pause**: When paused, `offerAgreement`, `offerAgreementUpdate`, `revokeOffer`, and `cancelAgreement` are blocked but reconcile/remove/maintain remain available

## Deployment

### Prerequisites

- GraphToken deployed
- PaymentsEscrow deployed
- RecurringCollector deployed
- IssuanceAllocator deployed and configured

### Deployment Sequence

1. Deploy ServiceAgreementManager implementation with constructor args (graphToken, paymentsEscrow, recurringCollector)
2. Deploy TransparentUpgradeableProxy with implementation and initialization data
3. Initialize with governor address
4. Grant `OPERATOR_ROLE` to the operator account that will offer agreements
5. Configure IssuanceAllocator to allocate tokens to ServiceAgreementManager (as an allocator-minting target)

### Verification

- Verify `PAYMENTS_ESCROW` and `RECURRING_COLLECTOR` immutables are set correctly
- Verify governor has `GOVERNOR_ROLE`
- Verify operator has `OPERATOR_ROLE`
- Verify ServiceAgreementManager supports `IIssuanceTarget`, `IContractApprover`, and `IServiceAgreementManager` interfaces
- Verify GRT token approvals work correctly with PaymentsEscrow
