# Disconnects

Gaps between [Design.md](./Design.md) and the merged codebase. Referenced from [Status.md](./Status.md).

## Major

### ~~1. Escrow Router does not exist~~

Moved to Resolved.

### ~~2. collect() signature mismatch → escrow key mapping~~

Moved to Resolved.

### ~~3. IS mints to msg.sender, skips GraphPayments distribution~~

Moved to Resolved.

### ~~4. No SubgraphService → IndexingSignal call path~~

Moved to Resolved. EscrowRouter handles routing — existing SS → IndexingAgreement → RC → escrow.collect() chain works unchanged.

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

### ~~1. Escrow Router does not exist~~

**Resolved**: EscrowRouter implemented at `packages/horizon/contracts/payments/EscrowRouter.sol`. Implements IPaymentsEscrow with governance-controlled override mapping per payer. Registered as "PaymentsEscrow" in Controller. Standard escrow by default; delegates collect()/getBalance() to override (IS) for IS-backed payers.

### ~~4. No SubgraphService → IndexingSignal call path~~

**Resolved**: EscrowRouter sits in the existing collect chain. SS → IndexingAgreement → RC → EscrowRouter.collect() → IS (for overridden payers). No changes to SS, RC, or IndexingAgreement needed.

### ~~5. IssuanceAllocator doesn't know about IS~~

**Decision**: IS minting is part of RM's allocation. IA has no awareness of IS and does not need to be deployed. The shared denominator ensures RM mints curation fraction, IS mints indexing fraction, total equals RM's full allocation. No accounting mismatch.

### ~~7. RCA creation is not automatic~~

**Decision**: Off-chain Dipper/IISA signs RCAs as authorized signer for depositor (via RC's Authorizable). Indexer accepts on-chain via existing SS.acceptIndexingAgreement(). No on-chain RCA automation. "Auto-created" in design doc means Dipper reacts to IS events automatically.

### ~~2. collect() signature mismatch → escrow key mapping~~

**Resolved**: Overloaded `IPaymentsEscrow.collect()` with `bytes32 collectionContext`. IS interprets context as `subgraphDeploymentID`. RC threads context from CollectParams. Existing callers (GraphTallyCollector) unchanged. See [CollectionContext.md](./CollectionContext.md).

### ~~3. IS mints to msg.sender, skips GraphPayments distribution~~

**Resolved**: IS now has two collect paths: (1) direct `IIndexingSignal.collect()` mints to msg.sender (existing), (2) `IPaymentsEscrow.collect()` with collectionContext — guarded by `msg.sender == ESCROW_ROUTER`, mints to self, approves GraphPayments, calls `GRAPH_PAYMENTS.collect()` for standard distribution (protocol tax, data service cut, delegation).
