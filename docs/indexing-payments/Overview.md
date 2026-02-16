# Indexing Payments Overview

Indexing payments allow data consumers (payers) to establish recurring payment agreements with indexers for continuous subgraph indexing services. This system enables predictable, metered payments based on indexing work performed.

## Quick Links

- [Architecture](./Architecture.md) - System components and relationships
- [Agreement Lifecycle](./AgreementLifecycle.md) - Creating, accepting, collecting, and canceling agreements
- [Payment Calculation](./PaymentCalculation.md) - How fees are computed
- [Integration Guide](./IntegrationGuide.md) - How to use the system

## Key Concepts

### Recurring Collection Agreement (RCA)

A signed, off-chain agreement between a payer and an indexer that specifies:

- **Rate limits**: Maximum tokens per second that can be collected
- **Collection windows**: Minimum and maximum time between collections
- **Duration**: When the agreement starts and ends
- **Pricing terms**: Base rate and per-entity rate for indexing work

### Indexing Agreement

The on-chain representation that links an RCA to a specific allocation. Each allocation can have at most one active indexing agreement.

### Collection

The act of claiming payment for indexing work performed. Collections require:

- Proof of Indexing (POI)
- Entity count
- Valid collection window timing

## Architecture Components

### Core Contracts

1. **RecurringCollector** - Manages RCA lifecycle, validates signatures, enforces rate limits
2. **IndexingAgreement** (library) - Links RCAs to allocations, calculates payment amounts
3. **SubgraphService** - Data service that orchestrates the system

### Payment Flow

```
Payer's Escrow → RecurringCollector → GraphPayments → Indexer + Delegators
```

## Benefits

### For Payers

- **Predictable costs**: Rate limits prevent unexpected charges
- **Pay for work**: Metered pricing based on entities indexed
- **Flexibility**: Update or cancel agreements as needs change
- **Security**: EIP-712 signatures and replay protection

### For Indexers

- **Recurring revenue**: Continuous payment stream for ongoing work
- **Automated collection**: Collect at regular intervals with proof of work
- **Multiple agreements**: Support multiple payers per allocation (future)

## Security Features

- **EIP-712 typed signatures** - Structured data signing prevents phishing
- **Nonce-based replay protection** - Prevents reuse of update messages
- **Rate limiting** - Caps extraction rate via `maxOngoingTokensPerSecond`
- **Collection windows** - Prevents too-frequent or too-late collections (≥600s window)
- **Slippage protection** - Configurable tolerance for rate-limited amounts
- **Stake locking** - Economic security proportional to fees collected
- **Deterministic agreement IDs** - Prevents ID collision attacks

## Status

This feature was implemented in commit `a7fb8758` and has undergone security auditing by Trust Security. All identified issues have been addressed in subsequent commits.

## Next Steps

- Read the [Architecture](./Architecture.md) document to understand system components
- Review the [Agreement Lifecycle](./AgreementLifecycle.md) for operational flows
- See the [Integration Guide](./IntegrationGuide.md) for implementation details
