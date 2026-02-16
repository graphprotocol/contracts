# Status

## Needs Review

These items need your decision or confirmation before work can proceed.

No open items.

## Decisions Made

| #   | Decision | Date | Rationale |
| --- | -------- | ---- | --------- |
| 2   | IS minting is part of RM allocation. IA has no awareness of IS, does not need to be deployed. RM does not under-mint — IS minting is RM-owned. | 2026-02-12 | Shared denominator ensures RM mints curation fraction, IS mints indexing fraction, total = full allocation. |
| 1   | EscrowRouter (option A): thin standalone contract implementing IPaymentsEscrow, registered as "PaymentsEscrow" in Controller. Default = standard escrow, override mapping per-payer delegates collect()/getBalance() to IS. | 2026-02-12 | IS virtual escrow needs to be callable through standard collect chain. Router avoids modifying RC/PE. |
| 3   | ~~RCA lifecycle: off-chain Dipper signs RCAs~~ **Superseded by #5/#6.** IS-as-payer + contract approver is now the primary RCA path. Operator prepares agreements on-chain via IS.prepareAgreement(); indexer accepts via SS.acceptIndexingAgreementFromContract(). EOA/Dipper path still works but is secondary. | 2026-02-12 (superseded 2026-02-16) | Original: RC's Authorizable supports delegated signing. Current: IS is the payer, contract approver bypasses ECDSA. |
| 5   | Contract approver support (Option B): IContractApprover (single callback) + RC.acceptFromContract() — no Authorizable changes. IS implements IContractApprover, prepareAgreement() stores hashes, isAuthorizedAgreement() confirms them. Indexer accepts via SS.acceptIndexingAgreementFromContract(). | 2026-02-16 | Removes ECDSA requirement for IS-originated agreements. On-chain, auditable authorization chain. EOA path unchanged. See [ContractAuthorization.md](./ContractAuthorization.md). |
| 6   | Per-agreement escrow model: escrow layer keyed on (subgraph, indexer), not (depositor, subgraph, indexer). AgreementEscrow { signal, accIssuanceSnapshot, accruedIssuance }. IS is the payer, not individual depositors. Signal layer (per-depositor positions and sets) unchanged. | 2026-02-16 | Removes per-depositor escrow complexity. One agreement per (subgraph, indexer). Standard reward-per-share pattern. |
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
- [x] Contract authorization analysis complete — see [ContractAuthorization.md](./ContractAuthorization.md)
- [x] Contract approver support implemented (IContractApprover, RC.acceptFromContract, SS, IS)
- [x] Per-agreement escrow model (AgreementEscrow, signal layer/escrow layer separation)
- [x] IS unit tests updated for per-agreement escrow model
- [x] Contract docs updated to match implementation
- [x] Bug fixes: deposit re-deposit guard, rounding in addSignal/withdraw, stale indexer set cleanup
- [x] Access control: direct collect removed (EscrowRouter-only), onRCACancelled gated with INDEXER_SET_OPERATOR_ROLE
- [x] Dead code removed (\_isInIndexerSet, IndexerNotInSet, IndexerSetEmpty)

## What's Not Done Yet

These are actual gaps — code that doesn't exist or hasn't been validated.

### Collection chain untested end-to-end

The collection path SS → IA → RC → EscrowRouter → IS → GraphPayments has never been run as a connected chain. Each piece compiles and has unit tests, but:
- No integration test exercises the full path
- EscrowRouter override for IS has never been configured in a test
- The RCA `payer` field must be IS's address for EscrowRouter routing — no test validates this

### Contract approver flow untested end-to-end

IS.prepareAgreement → SS.acceptIndexingAgreementFromContract → RC.acceptFromContract → IS.isAuthorizedAgreement has never been run as a chain. Specifically:
- No test constructs a valid RCA, hashes it, and exercises the full acceptance flow
- No test validates that RC.acceptFromContract correctly calls back IS

### RC authorization model open question

`RC.acceptFromContract` accepts any contract that returns the magic value. No governance whitelist restricts which contracts can act as approvers. Current trust relies on SS access control (msg.sender == rca.dataService). See [ContractAuthorization.md](./ContractAuthorization.md#open-questions).

### ~~IS access control for collect and onRCACancelled~~

Resolved. Direct `collect(bytes32, address, uint256)` removed — EscrowRouter is the only collection path. `onRCACancelled` gated with `INDEXER_SET_OPERATOR_ROLE`.

### ~~Decision #3 partially superseded~~

Resolved. Decision #3 updated to note supersession by #5/#6. IS-as-payer + contract approver is now the primary RCA path.

## Contract Status

| Contract                                                | File                                                                    | Status                                  |
| ------------------------------------------------------- | ----------------------------------------------------------------------- | --------------------------------------- |
| [IndexingSignal](./contracts/IndexingSignal.md)         | `packages/issuance/contracts/signal/IndexingSignal.sol`                 | Per-agreement escrow, IContractApprover, access-controlled, unit tested |
| [RewardsManager](./contracts/RewardsManager.md)         | `packages/contracts/contracts/rewards/RewardsManager.sol`               | Updated, combined signal works          |
| [EscrowRouter](./contracts/EscrowRouter.md)             | `packages/horizon/contracts/payments/EscrowRouter.sol`                  | Implemented with collectionContext      |
| [SubgraphService](./contracts/SubgraphService.md)       | `packages/subgraph-service/contracts/SubgraphService.sol`               | acceptFromContract path added           |
| [RecurringCollector](./contracts/RecurringCollector.md) | `packages/horizon/contracts/payments/collectors/RecurringCollector.sol` | acceptFromContract + refactored accept  |
| [PaymentsEscrow](./contracts/PaymentsEscrow.md)         | `packages/horizon/contracts/payments/PaymentsEscrow.sol`                | Overloaded collect() added              |
