# lastPoiBlockNumber: On-Chain Indexing Progress

## Motivation

`lastCollectionAt` (RC, timestamp) tells you _when_ the indexer last collected. It doesn't tell you _how far_ they've indexed. `poiBlockNumber` — already presented in every collection and emitted in `IndexingFeesCollectedV1` — tells you that, but is not stored.

Storing it gives an on-chain liveness signal for indexing progress, useful for:

- **Staleness detection**: payers or SAM operators comparing `lastPoiBlockNumber` to current block to decide whether to cancel
- **Race condition mitigation**: gating cancellation with a freshness check, so an off-chain "cancel for lack of progress" decision doesn't race with an on-chain collection that proves progress

## Where

`IndexingAgreement.StorageManager` — either as a new field in `IIndexingAgreement.State` or a new mapping:

```solidity
struct StorageManager {
  mapping(bytes16 agreementId => IIndexingAgreement.State) agreements;
  mapping(bytes16 agreementId => IndexingAgreementTermsV1 data) termsV1;
  mapping(address allocationId => bytes16 agreementId) allocationToActiveAgreementId;
}
```

Adding to `State` is simplest — it's already returned by `get()`, so external consumers get it for free:

```solidity
struct State {
  address allocationId;
  IndexingAgreementVersion version;
  uint256 lastPoiBlockNumber;
}
```

## How

One line in `IndexingAgreement.collect()`, after RC collection succeeds:

```solidity
self.agreements[params.agreementId].lastPoiBlockNumber = data.poiBlockNumber;
```

The data is already decoded from `CollectIndexingFeeDataV1` at that point.

## Not in RC

RC is a payment primitive — it tracks temporal state (`lastCollectionAt`) and rate limits. POI block numbers are domain-specific to indexing. Keeping them in SS preserves clean layering and RC reusability for other data services.
