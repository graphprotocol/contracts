# Status

## Needs Review

These items need your decision or confirmation before work can proceed.

| #   | Topic                       | Question                                                                                                                                  | Context                                                           |
| --- | --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| 1   | Collection plumbing         | How should IS-minted GRT reach GraphPayments for distribution? See [Disconnects #1-#4](./Disconnects.md)                                  | Router? IS calls GraphPayments directly? New collector?           |
| 2   | IssuanceAllocator awareness | Should IssuanceAllocator know about IS, or does IS remain invisible (piggybacking on RM's rate)? See [Disconnects #5](./Disconnects.md)   | Affects accounting and whether IS needs its own allocation target |
| 3   | RCA lifecycle               | How are RCAs created for depositor-indexer pairs? Fully off-chain signing, or on-chain automation? See [Disconnects #7](./Disconnects.md) | RecurringCollector requires EIP712-signed RCAs                    |

## Decisions Made

| #   | Decision   | Date | Rationale |
| --- | ---------- | ---- | --------- |
| —   | (none yet) |      |           |

## What's Done

- [x] IndexingSignal contract implemented (virtual escrow, accumulators, indexer sets)
- [x] RewardsManager updated for combined signal (`_getTotalSignal()`, `IIndexingSignalReadOnly`)
- [x] IssuanceAllocator implemented (multi-target allocation with self-minting support)
- [x] Unit tests for IS core (deposit, withdraw, issuance accumulation, collection, indexer sets)
- [x] Indexing payments branch merged (RecurringCollector, IndexingAgreement in SubgraphService)
- [x] Disconnect analysis complete — see [Disconnects.md](./Disconnects.md)

## What's Next

1. Resolve Needs Review items above (design decisions)
2. Design and implement collection integration (Escrow Router or alternative)
3. Ensure IS.collect() distributes via GraphPayments
4. Integration tests for end-to-end collection flow
5. Update contract docs to match final implementation

## Contract Status

| Contract                                                | File                                                                    | Status                                  |
| ------------------------------------------------------- | ----------------------------------------------------------------------- | --------------------------------------- |
| [IndexingSignal](./contracts/IndexingSignal.md)         | `packages/issuance/contracts/signal/IndexingSignal.sol`                 | Core done, collection integration TBD   |
| [RewardsManager](./contracts/RewardsManager.md)         | `packages/contracts/contracts/rewards/RewardsManager.sol`               | Updated, combined signal works          |
| [EscrowRouter](./contracts/EscrowRouter.md)             | Does not exist yet                                                      | Design needed                           |
| [SubgraphService](./contracts/SubgraphService.md)       | `packages/subgraph-service/contracts/SubgraphService.sol`               | Has IndexingFee path, no IS integration |
| [RecurringCollector](./contracts/RecurringCollector.md) | `packages/horizon/contracts/payments/collectors/RecurringCollector.sol` | Merged, calls PaymentsEscrow directly   |
| [PaymentsEscrow](./contracts/PaymentsEscrow.md)         | `packages/horizon/contracts/payments/PaymentsEscrow.sol`                | Existing, no changes planned            |
