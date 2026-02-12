# Status

## Needs Review

These items need your decision or confirmation before work can proceed.

No open items.

## Decisions Made

| #   | Decision | Date | Rationale |
| --- | -------- | ---- | --------- |
| 2   | IS minting is part of RM allocation. IA has no awareness of IS, does not need to be deployed. RM does not under-mint — IS minting is RM-owned. | 2026-02-12 | Shared denominator ensures RM mints curation fraction, IS mints indexing fraction, total = full allocation. |
| 1   | EscrowRouter (option A): thin standalone contract implementing IPaymentsEscrow, registered as "PaymentsEscrow" in Controller. Default = standard escrow, override mapping per-payer delegates collect()/getBalance() to IS. | 2026-02-12 | IS virtual escrow needs to be callable through standard collect chain. Router avoids modifying RC/PE. |
| 3   | RCA lifecycle: off-chain Dipper signs RCAs as authorized signer for depositor, offers to indexer. Indexer accepts via existing SS.acceptIndexingAgreement(). No on-chain RCA automation needed. | 2026-02-12 | RC's Authorizable supports delegated signing. Existing accept/cancel/update flow works. Dipper orchestrates. |
| 4   | Escrow key mapping: overloaded `IPaymentsEscrow.collect()` with `bytes32 collectionContext`. IS interprets as subgraphDeploymentID. Existing signature unchanged. Caller context (msg.sender) not needed by IS — virtual escrow has no per-collector dimension. | 2026-02-12 | See [CollectionContext.md](./CollectionContext.md). RC threads context from CollectParams. GraphTallyCollector unchanged. |

## What's Done

- [x] IndexingSignal contract implemented (virtual escrow, accumulators, indexer sets)
- [x] RewardsManager updated for combined signal (`_getTotalSignal()`, `IIndexingSignalReadOnly`)
- [x] IssuanceAllocator implemented (multi-target allocation with self-minting support)
- [x] Unit tests for IS core (deposit, withdraw, issuance accumulation, collection, indexer sets)
- [x] Indexing payments branch merged (RecurringCollector, IndexingAgreement in SubgraphService)
- [x] Disconnect analysis complete — see [Disconnects.md](./Disconnects.md)
- [x] EscrowRouter implemented — see [EscrowRouter.md](./contracts/EscrowRouter.md)
- [x] CollectionContext design complete — see [CollectionContext.md](./CollectionContext.md)
- [x] All design decisions resolved (#1-#4)
- [x] `collectionContext` threaded through chain (IPaymentsEscrow, RC, EscrowRouter, IA, PE)
- [x] IS updated with IPaymentsEscrow escrow collect (msg.sender == router guard, GraphPayments distribution)

## What's Next

1. Integration tests for end-to-end collection flow (SS → IA → RC → EscrowRouter → IS → GraphPayments)
2. Update contract docs to match final implementation

## Contract Status

| Contract                                                | File                                                                    | Status                                  |
| ------------------------------------------------------- | ----------------------------------------------------------------------- | --------------------------------------- |
| [IndexingSignal](./contracts/IndexingSignal.md)         | `packages/issuance/contracts/signal/IndexingSignal.sol`                 | Escrow collect implemented, compiles    |
| [RewardsManager](./contracts/RewardsManager.md)         | `packages/contracts/contracts/rewards/RewardsManager.sol`               | Updated, combined signal works          |
| [EscrowRouter](./contracts/EscrowRouter.md)             | `packages/horizon/contracts/payments/EscrowRouter.sol`                  | Implemented with collectionContext      |
| [SubgraphService](./contracts/SubgraphService.md)       | `packages/subgraph-service/contracts/SubgraphService.sol`               | Has IndexingFee path, no IS integration |
| [RecurringCollector](./contracts/RecurringCollector.md) | `packages/horizon/contracts/payments/collectors/RecurringCollector.sol` | collectionContext threaded              |
| [PaymentsEscrow](./contracts/PaymentsEscrow.md)         | `packages/horizon/contracts/payments/PaymentsEscrow.sol`                | Overloaded collect() added              |
