# Agreement Lifecycle

This document describes the complete lifecycle of an indexing agreement, from creation through cancellation.

## State Machine

```mermaid
stateDiagram-v2
    [*] --> NotAccepted: RCA signed off-chain
    NotAccepted --> Accepted: accept()
    Accepted --> Accepted: collect()
    Accepted --> Accepted: update()
    Accepted --> CanceledByServiceProvider: cancel() by indexer
    Accepted --> CanceledByPayer: cancelByPayer()
    Accepted --> CanceledByServiceProvider: allocation closes normally
    Accepted --> CanceledByServiceProvider: allocation force closed
    CanceledByPayer --> CanceledByPayer: collect() (final)
    CanceledByServiceProvider --> [*]
    CanceledByPayer --> [*]
```

### State Descriptions

| State                       | Description                                 | Collectable |
| --------------------------- | ------------------------------------------- | ----------- |
| `NotAccepted`               | RCA signed but not yet accepted on-chain    | No          |
| `Accepted`                  | Active agreement, normal operation          | Yes         |
| `CanceledByServiceProvider` | Indexer canceled, no further collections    | No          |
| `CanceledByPayer`           | Payer canceled, allows one final collection | Yes         |

## 1. Agreement Creation and Acceptance

### Sequence Diagram

```mermaid
sequenceDiagram
    participant P as Payer
    participant I as Indexer
    participant SS as SubgraphService
    participant IA as IndexingAgreement
    participant RC as RecurringCollector
    participant AS as Allocation Storage

    Note over P: Off-chain preparation
    P->>P: Create RCA with terms
    P->>P: Sign RCA (EIP-712)
    P->>I: Send signed RCA

    Note over I: On-chain acceptance
    I->>SS: acceptIndexingAgreement(allocationId, signedRCA)
    SS->>SS: Validate indexer registered
    SS->>SS: Validate provision

    SS->>IA: accept(allocations, allocationId, signedRCA)
    IA->>AS: Get allocation
    IA->>IA: Validate allocation open & owned by indexer
    IA->>IA: Validate dataService == this
    IA->>IA: Decode metadata → terms
    IA->>IA: Generate agreementId
    IA->>IA: Validate no existing agreement
    IA->>IA: Validate deployment ID match
    IA->>IA: Check allocation has no active agreement
    IA->>IA: Store agreement state
    IA->>IA: Store terms (V1)
    IA->>IA: Link allocation → agreementId

    IA->>RC: accept(signedRCA)
    RC->>RC: Validate deadline not elapsed
    RC->>RC: Verify signature
    RC->>RC: Validate addresses not zero
    RC->>RC: Validate collection window params
    RC->>RC: Create agreement storage
    RC->>RC: state = Accepted
    RC-->>IA: agreementId

    IA-->>SS: agreementId
    SS-->>I: agreementId

    Note over IA: Events emitted
    IA->>IA: emit IndexingAgreementAccepted
    RC->>RC: emit AgreementAccepted
```

### Acceptance Requirements

**Allocation Requirements**:

- Must exist and be open (`createdAtEpoch != 0 && closedAtEpoch == 0`)
- Must be owned by the indexer in the RCA
- `subgraphDeploymentId` must match RCA metadata
- Cannot have another active agreement

**RCA Requirements**:

- `deadline ≥ block.timestamp`
- `dataService` must be SubgraphService address
- `payer`, `dataService`, `serviceProvider` must be non-zero
- Valid payer signature (or authorized signer)
- `endsAt > block.timestamp`
- `maxSecondsPerCollection - minSecondsPerCollection ≥ 600`
- `endsAt - block.timestamp ≥ minSecondsPerCollection + 600`

**Terms Requirements**:

- `tokensPerSecond ≤ maxOngoingTokensPerSecond`

## 2. Payment Collection

### Sequence Diagram

```mermaid
sequenceDiagram
    participant I as Indexer
    participant SS as SubgraphService
    participant IA as IndexingAgreement
    participant RC as RecurringCollector
    participant GPE as GraphPaymentsEscrow
    participant GP as GraphPayments

    I->>SS: collect(indexer, agreementId, data)
    SS->>IA: collect(CollectParams)

    IA->>IA: Get agreement wrapper
    IA->>IA: Get allocation
    IA->>IA: Validate indexer owns allocation

    IA->>RC: getCollectionInfo(agreement)
    RC->>RC: Check state (Accepted or CanceledByPayer)
    RC->>RC: Calculate collection window
    RC->>RC: collectionSeconds = now - lastCollectionAt
    RC-->>IA: (isCollectable, collectionSeconds, reason)

    IA->>IA: Validate collectable
    IA->>IA: Decode collection data (entities, POI, etc)
    IA->>IA: Calculate expected tokens
    Note over IA: expectedTokens = collectionSeconds *<br>(tokensPerSecond + tokensPerEntityPerSecond * entities)

    IA->>RC: collect(CollectParams)
    RC->>RC: getCollectionInfo(agreement)
    RC->>RC: Validate collection window
    RC->>RC: Calculate max allowed tokens
    Note over RC: maxTokens = maxOngoingTokensPerSecond * collectionSeconds<br>+ (firstCollection ? maxInitialTokens : 0)
    RC->>RC: tokensToCollect = min(expectedTokens, maxTokens)
    RC->>RC: Validate slippage ≤ maxSlippage
    RC->>RC: lastCollectionAt = now

    RC->>GPE: collect(paymentType, payer, serviceProvider, tokens, ...)
    GPE->>GP: pay(...)
    GP-->>GPE: success
    GPE-->>RC: success

    RC-->>IA: tokensCollected
    IA->>IA: emit IndexingFeesCollectedV1
    RC->>RC: emit RCACollected

    IA-->>SS: tokensCollected
    SS->>SS: Lock stake (tokensCollected * stakeToFeesRatio)
    SS-->>I: tokensCollected
```

### Collection Requirements

**Timing Requirements**:

- Agreement in `Accepted` or `CanceledByPayer` state
- `collectionSeconds ≥ minSecondsPerCollection` (unless canceled/expired)
- `collectionSeconds ≤ maxSecondsPerCollection`

**Validation Requirements**:

- Indexer must own the allocation
- Allocation must be open
- Indexer must have active provision with SubgraphService
- `tokensAvailable > 0` for indexer with data service

**Data Requirements**:

- Valid entities count (uint256)
- Valid POI (bytes32)
- Valid POI block number (uint256)
- Optional metadata (bytes)
- Max slippage tolerance (uint256)

### Payment Calculation

See [Payment Calculation](./PaymentCalculation.md) for detailed formulas.

## 3. Agreement Update

### Sequence Diagram

```mermaid
sequenceDiagram
    participant P as Payer
    participant I as Indexer
    participant SS as SubgraphService
    participant IA as IndexingAgreement
    participant RC as RecurringCollector

    Note over P: Off-chain preparation
    P->>P: Create RCAU with new terms
    P->>P: nonce = currentNonce + 1
    P->>P: Sign RCAU (EIP-712)
    P->>I: Send signed RCAU

    Note over I: On-chain update
    I->>SS: updateIndexingAgreement(indexer, signedRCAU)
    SS->>SS: Validate indexer

    SS->>IA: update(indexer, signedRCAU)
    IA->>IA: Get agreement wrapper
    IA->>IA: Validate state == Accepted
    IA->>IA: Validate serviceProvider == indexer
    IA->>IA: Decode update metadata
    IA->>IA: Validate terms against RCA limits
    IA->>IA: Update stored terms

    IA->>RC: update(signedRCAU)
    RC->>RC: Validate deadline not elapsed
    RC->>RC: Validate state == Accepted
    RC->>RC: Validate dataService == msg.sender
    RC->>RC: Verify signature
    RC->>RC: Validate nonce == updateNonce + 1
    RC->>RC: Validate collection window params
    RC->>RC: Update agreement storage
    RC->>RC: updateNonce = rcau.nonce
    RC->>RC: emit AgreementUpdated

    RC-->>IA: success
    IA->>IA: emit IndexingAgreementUpdated
    IA-->>SS: success
    SS-->>I: success
```

### Update Requirements

- Agreement must be in `Accepted` state
- Indexer must be the service provider
- Valid payer signature (or authorized signer)
- Nonce must be exactly `currentNonce + 1`
- New terms must satisfy all RCA constraints
- Updated pricing applies immediately to next collection

### Important Note

**Updated terms apply retroactively** to the period since `lastCollectionAt`. This means the next collection will use the new rates for the entire duration since the last collection.

## 4. Agreement Cancellation

### By Indexer

```mermaid
sequenceDiagram
    participant I as Indexer
    participant SS as SubgraphService
    participant IA as IndexingAgreement
    participant RC as RecurringCollector

    I->>SS: cancelIndexingAgreement(indexer, agreementId)
    SS->>SS: Validate indexer

    SS->>IA: cancel(indexer, agreementId)
    IA->>IA: Get agreement wrapper
    IA->>IA: Validate state == Accepted
    IA->>IA: Validate serviceProvider == indexer
    IA->>IA: Delete allocationToActiveAgreementId link

    IA->>RC: cancel(agreementId, CancelAgreementBy.ServiceProvider)
    RC->>RC: Validate state == Accepted
    RC->>RC: Validate dataService == msg.sender
    RC->>RC: canceledAt = now
    RC->>RC: state = CanceledByServiceProvider
    RC->>RC: emit AgreementCanceled

    RC-->>IA: success
    IA->>IA: emit IndexingAgreementCanceled
    IA-->>SS: success
    SS-->>I: success

    Note over I,RC: No further collections possible
```

### By Payer

```mermaid
sequenceDiagram
    participant P as Payer
    participant SS as SubgraphService
    participant IA as IndexingAgreement
    participant RC as RecurringCollector

    P->>SS: cancelIndexingAgreementByPayer(agreementId)

    SS->>IA: cancelByPayer(agreementId)
    IA->>IA: Get agreement wrapper
    IA->>IA: Validate state == Accepted
    IA->>RC: isAuthorized(payer, msg.sender)
    RC-->>IA: true/false
    IA->>IA: Require authorized
    IA->>IA: Delete allocationToActiveAgreementId link

    IA->>RC: cancel(agreementId, CancelAgreementBy.Payer)
    RC->>RC: Validate state == Accepted
    RC->>RC: Validate dataService == msg.sender
    RC->>RC: canceledAt = now
    RC->>RC: state = CanceledByPayer
    RC->>RC: emit AgreementCanceled

    RC-->>IA: success
    IA->>IA: emit IndexingAgreementCanceled
    IA-->>SS: success
    SS-->>P: success

    Note over P,RC: Final collection still possible
```

### Automatic Cancellation on Allocation Close

```mermaid
sequenceDiagram
    participant I as Indexer
    participant SS as SubgraphService
    participant IA as IndexingAgreement
    participant RC as RecurringCollector

    I->>SS: stopService() or closeAllocation()
    SS->>SS: Close allocation

    SS->>IA: onCloseAllocation(allocationId, forceClosed)
    IA->>IA: agreementId = allocationToActiveAgreementId[allocation]

    alt agreementId exists
        IA->>IA: Get agreement wrapper

        alt wrapper is active
            IA->>IA: Delete allocationToActiveAgreementId link

            alt forceClosed
                IA->>RC: cancel(agreementId, CancelAgreementBy.ThirdParty)
            else normal close
                IA->>RC: cancel(agreementId, CancelAgreementBy.ServiceProvider)
            end

            RC->>RC: canceledAt = now
            RC->>RC: state = CanceledByServiceProvider
            RC->>RC: emit AgreementCanceled

            IA->>IA: emit IndexingAgreementCanceled
        end
    end
```

### Cancellation Effects

| Canceled By               | Resulting State             | Further Collections | Allocation Link |
| ------------------------- | --------------------------- | ------------------- | --------------- |
| Service Provider          | `CanceledByServiceProvider` | No                  | Removed         |
| Payer                     | `CanceledByPayer`           | Yes (one final)     | Removed         |
| Allocation Close (normal) | `CanceledByServiceProvider` | No                  | Removed         |
| Allocation Close (forced) | `CanceledByServiceProvider` | No                  | Removed         |

## Edge Cases and Special Behaviors

### Collection After Payer Cancellation

When payer cancels (`CanceledByPayer` state), one final collection is allowed:

- `collectionSeconds` calculated up to `min(canceledAt, endsAt)`
- `minSecondsPerCollection` requirement waived
- `maxSecondsPerCollection` still enforced

### Collection After Agreement Expiry

When `block.timestamp > endsAt`:

- `collectionSeconds` calculated up to `endsAt`
- `minSecondsPerCollection` requirement waived
- `maxSecondsPerCollection` still enforced

### Zero-Token Collections

Collections with `entities = 0` and `poi = bytes32(0)` are allowed and result in zero tokens collected. This allows indexers to "checkpoint" the agreement without claiming payment.

### Over-Allocation

If allocation is resized down such that `tokens < existingCommitments`, the agreement is automatically canceled by the SubgraphService to prevent over-commitment.

## Related Documentation

- [Architecture](./Architecture.md) - System components and relationships
- [Payment Calculation](./PaymentCalculation.md) - Fee computation details
- [Integration Guide](./IntegrationGuide.md) - Implementation examples
