# Collection Context

## Problem

When EscrowRouter delegates `collect()` to IS, IS needs `subgraphDeploymentID` to compute the virtual balance. The current `IPaymentsEscrow.collect()` signature doesn't carry it, and `(payer, receiver)` alone is ambiguous (depositor can have the same indexer for multiple subgraphs).

## Solution

Add an **overloaded** `collect()` to `IPaymentsEscrow` with a `bytes32 collectionContext` parameter. The existing signature stays unchanged — callers that don't need context continue using it. The new overload is used by RC to thread context through.

```solidity
// Existing (unchanged)
function collect(
    PaymentTypes paymentType,
    address payer,
    address receiver,
    uint256 tokens,
    address dataService,
    uint256 dataServiceCut,
    address receiverDestination
) external;

// New overload
function collect(
    PaymentTypes paymentType,
    address payer,
    address receiver,
    uint256 tokens,
    address dataService,
    uint256 dataServiceCut,
    address receiverDestination,
    bytes32 collectionContext
) external;
```

### Caller Context (msg.sender) Resolution

When EscrowRouter delegates to IS, `msg.sender` from IS's perspective is the router, not RC. **This is fine** — IS doesn't need the collector identity:

- **Standard flows**: Router IS the escrow. RC calls it directly → `msg.sender` = RC → used as collector key. Identical to PaymentsEscrow.
- **Override flows**: IS validates `(payer, collectionContext, receiver)` against signal state. The collector dimension is irrelevant for virtual escrow — IS has no per-collector accounts.
- **Mint protection**: IS checks `msg.sender == escrowRouter`. The authorization chain (SS → RC → Router) is already validated upstream.

No changes to the existing `IPaymentsEscrow.collect()` caller convention.

## Data Flow

```
SubgraphService (IndexingAgreement.collect)
  │  has: allocation.subgraphDeploymentId
  │  sets: collectionContext = allocation.subgraphDeploymentId
  ▼
RecurringCollector._collect()
  │  receives: collectionContext in CollectParams
  │  threads through to escrow call (does not interpret)
  ▼
EscrowRouter.collect()
  │  has override for payer? → delegates to IS with collectionContext
  │  no override? → standard escrow (ignores collectionContext)
  ▼
IndexingSignal.collect() [IPaymentsEscrow interface]
  │  payer = depositor
  │  receiver = indexer
  │  collectionContext = subgraphDeploymentID
  │  → computes virtual balance for (depositor, subgraph, indexer)
  │  → mints GRT, distributes via GraphPayments
```

## Security Analysis

### Who can trigger a collection?

The chain of authorization:

| Layer | What it enforces | How |
|-------|-----------------|-----|
| **SubgraphService** | Only registered indexers with valid provisions can collect | `onlyAuthorizedForProvision`, `onlyRegisteredIndexer` modifiers |
| **IndexingAgreement** | Allocation must be open, belong to the indexer, and have an active agreement | `_requireValidAllocation`, agreement state checks |
| **RecurringCollector** | Only the agreement's dataService (SS) can call collect. Rate limits, temporal windows, agreement state. | `msg.sender == agreement.dataService` (line 331), `_requireValidCollect`, `_getCollectionInfo` |
| **EscrowRouter** | Routes to correct escrow. Standard: physical balance check. Override: delegates to IS. | `escrowOverrides[payer]` lookup |
| **IndexingSignal** | Payer has signal for this subgraph, receiver is in payer's indexer set, virtual balance is sufficient | Validates (payer, collectionContext, receiver) against its state |

### Can an attacker manipulate collectionContext?

**No.** The context flows from SubgraphService, which sets it from `allocation.subgraphDeploymentId` (IndexingAgreement.sol line 581). The allocation's subgraph was validated at accept time — it must match the RCA metadata (line 313). RC threads the context through without modification. Only SS can call RC.collect() (line 331: `msg.sender == agreement.dataService`).

An attacker would need to either:
- Control SubgraphService (not possible — it's a protocol contract)
- Call RC.collect() directly (blocked — RC checks msg.sender == dataService)
- Create a fake agreement (blocked — requires EIP712 signature from authorized payer)

### Can someone collect for a subgraph they don't have signal for?

**No.** IS validates the full tuple `(payer, collectionContext/subgraph, receiver/indexer)`:
- Payer must have a signal position for this subgraph
- Receiver must be in the payer's indexer set for this subgraph
- Virtual balance must be sufficient

### Can someone collect more than entitled?

**No.** Double protection:
- RC enforces `maxOngoingTokensPerSecond × collectionSeconds` rate limit
- IS enforces virtual balance limit (accumulated issuance since last collection)
- Collection is capped at `min(RC_allowed, IS_virtual_balance)`

### What values flow through?

| Parameter | Source | Verified by |
|-----------|--------|-------------|
| `payer` | RCA (signed by payer/authorized signer) | RC: stored in accepted agreement |
| `receiver` | RCA (serviceProvider field) | RC: stored in accepted agreement |
| `tokens` | RC: min(requested, rate-limited max) | RC + IS |
| `dataService` | RCA (SubgraphService address) | RC: `msg.sender == agreement.dataService` |
| `collectionContext` | SS: `allocation.subgraphDeploymentId` | IS: validates against signal state |

### getBalance() consideration

`IPaymentsEscrow.getBalance(payer, collector, receiver)` doesn't have a context parameter. Options:
1. Add `bytes32 collectionContext` to getBalance() too (consistent)
2. IS returns total virtual balance across all subgraphs for this (payer, receiver) pair (conservative)
3. IS provides separate `getVirtualBalance(depositor, subgraph, indexer)` for precise queries

Recommendation: option 1 for consistency. getBalance() is informational (not in the collect critical path — RC doesn't call it before collecting).

## Changes Required

| Contract | Change |
|----------|--------|
| `IPaymentsEscrow` | Add overloaded `collect()` with `bytes32 collectionContext`. Existing signature unchanged. |
| `IRecurringCollector.CollectParams` | Add `bytes32 collectionContext` field |
| `RecurringCollector._collect()` | Call new overloaded `escrow.collect(...)` with `_params.collectionContext` |
| `GraphTallyCollector._collect()` | No change — continues calling existing `collect()` (no context needed) |
| `EscrowRouter` | Implement both `collect()` overloads. Context version threads to override; standard ignores context. |
| `PaymentsEscrow` | Implement overloaded `collect()` — delegates to existing logic, ignores context. |
| `IndexingSignal` | Implement `IPaymentsEscrow.collect()` (context version) using collectionContext as subgraphDeploymentID |
| `IndexingAgreement.collect()` | Set `collectionContext = allocation.subgraphDeploymentId` in CollectParams |

## Navigation

- [Status.md](./Status.md)
- [EscrowRouter](./contracts/EscrowRouter.md)
- [IndexingSignal](./contracts/IndexingSignal.md)
- [RecurringCollector](./contracts/RecurringCollector.md)
