# Disconnects

Gaps between [Design.md](./Design.md) and the merged codebase. Referenced from [Status.md](./Status.md).

## Major

### 1. Escrow Router does not exist

Design describes a governance-controlled router that intercepts escrow calls and delegates IS-backed flows to IndexingSignal. No such contract exists. RecurringCollector calls `_graphPaymentsEscrow().collect()` directly via immutable GraphDirectory reference.

**Impact**: No mechanism to route IS-backed collections to IndexingSignal.

### 2. collect() signature mismatch

PaymentsEscrow.collect():
```
(PaymentTypes, address payer, address receiver, uint256 tokens,
 address dataService, uint256 dataServiceCut, address receiverDestination)
```

IndexingSignal.collect():
```
(address depositor, bytes32 subgraphDeploymentID, address indexer, uint256 amount)
```

IS needs `subgraphDeploymentID` which PaymentsEscrow doesn't take. A transparent proxy router cannot bridge these without signature translation.

**Impact**: Router pattern from design doc won't work as specified.

### 3. IS mints to msg.sender, skips GraphPayments distribution

`IndexingSignal.collect()` calls `GRAPH_TOKEN.mint(msg.sender, collectedTokens)` — no protocol tax, no data service cut, no delegation pool distribution. PaymentsEscrow handles this via `_graphPayments().collect(...)`.

**Impact**: IS-minted tokens bypass the standard payment distribution pipeline.

### 4. No SubgraphService → IndexingSignal call path

SubgraphService has `IndexingFee` payment type routing through `IndexingAgreement → RecurringCollector → PaymentsEscrow`. No point in this chain calls IndexingSignal.

**Impact**: End-to-end collection flow is broken for IS-backed indexing fees.

## Medium

### 5. IssuanceAllocator doesn't know about IS

IS reads `REWARDS_MANAGER.getAllocatedIssuancePerBlock()` and applies it to indexing signal's fraction. The math works (RM mints curation fraction, IS mints indexing fraction, they sum correctly). But IssuanceAllocator allocated that rate to RM alone — IS minting is untracked from the allocator's perspective.

**Impact**: Accounting mismatch if IssuanceAllocator audits or reconciles actual mints vs allocations.

### 6. RecurringCollector reference path stale

Design references `/git/graphprotocol/contracts/indexing-payments/...`. Actual path after merge: `packages/horizon/contracts/payments/collectors/RecurringCollector.sol`.

**Impact**: Doc-only. Trivial fix.

### 7. RCA creation is not automatic

Design says "RCAs auto-created" for depositor-indexer pairs. RecurringCollector requires EIP712-signed `SignedRCA` structs accepted via `accept()`. IS manages indexer sets but doesn't interact with RecurringCollector at all.

**Impact**: Off-chain process needed to sign/offer RCAs. Design doc implies more automation than exists.

## Resolved

(None yet — items move here as they're addressed.)
