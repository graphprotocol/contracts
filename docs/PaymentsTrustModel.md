# Payments Trust Model

This document describes the trust assumptions between the five core actors in the Graph Horizon payments protocol: **payer**, **collector**, **data service**, **receiver**, and **escrow**. The general model is described first, followed by specifics of the current implementation (RecurringCollector, SubgraphService, RAM).

## Trust Summary

| Relationship                | Trust                                     | Mitigation                                       |
| --------------------------- | ----------------------------------------- | ------------------------------------------------ |
| Payer → Collector           | Enforces agreed caps                      | Protocol-deployed; escrow caps absolute exposure |
| Payer → Receiver            | Claimed work is honest                    | Post-hoc disputes + stake locking                |
| Receiver → Payer (EOA)      | Escrow stays funded                       | Thaw period; on-chain visibility                 |
| Receiver → Payer (contract) | Escrow stays funded; not block collection | RecurringAgreementManager: protocol-deployed     |
| Receiver → Collector        | Correctly caps and forwards payment       | Protocol-deployed; code is transparent           |
| Receiver → Data Service     | Correct computation; not paused           | Protocol-deployed; code is transparent           |
| Receiver → Escrow           | Releases funds on valid collection        | Stateless; no discretionary logic                |
| Data Service ↔ Collector    | Each trusts the other's domain            | Two-layer capping; independent validation        |

## Actors

| Actor            | Role                                                                    | Examples                                                                    |
| ---------------- | ----------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| **Payer**        | Funds escrow; authorizes collector contracts                            | RecurringAgreementManager (protocol-managed), external payer (ECDSA-signed) |
| **Collector**    | Validates payment requests; enforces per-agreement caps                 | RecurringCollector                                                          |
| **Data service** | Entry point for collection; computes amounts earned                     | SubgraphService                                                             |
| **Receiver**     | Service provider receiving payment                                      | Indexer                                                                     |
| **Escrow**       | Holds GRT per (payer, collector, receiver) tuple; enforces thaw periods | PaymentsEscrow                                                              |

## Payment Flow (General Model)

```
│ Receiver
└─> Data Service.collect(work done)
    └─> Collector.collect(tokens earned)
        │ validates payment terms, caps amount
        └─> PaymentsEscrow.collect(tokens to collect)
            └─> GraphPayments.collect(tokens collected)
                │ distributes to: protocol (burned), data service, delegation pool, receiver
            <───┘
        <───┘
    <───┘
<───┘
```

Any data service and collector can plug into this flow. The PaymentsEscrow and GraphPayments layers are fixed protocol infrastructure. The data service computes its own token amount; the collector independently caps it; the actual payment is `min(tokens earned, agreement cap)`, and escrow reverts if balance is insufficient.

### RecurringCollector Extensions

RecurringCollector adds payer callbacks when the payer is a contract:

```
│ Receiver
└─> Data Service.collect(work done)
    └─> RecurringCollector.collect(tokens earned)
        │ validates agreement terms, caps amount
        │ validates receiver has active provision with data service
        │ if 0 < tokensToCollect AND payer is contract:
        │   if implements IProviderEligibility:
        │     require payer.isEligible(receiver)    ← can BLOCK
        │   try payer.beforeCollection(id, tokens)  (can't block)
        └─> PaymentsEscrow.collect(tokens to collect)
            └─> GraphPayments.collect(tokens collected)
                │ distributes to: protocol (burned), data service, delegation pool, receiver
            <───┘
        <───┘
        │ if payer is contract:                     (even if tokensToCollect == 0)
        │   try payer.afterCollection(id, tokens)   (can't block)
    <───┘
<───┘
```

- **`isEligible`**: hard `require` — contract payer can block collection for ineligible receivers. Only called when `0 < tokensToCollect`.
- **`beforeCollection`**: try-catch — allows payer to top up escrow (RAM uses this for JIT deposits), but cannot block (though a malicious contract payer could consume excessive gas). Only called when `0 < tokensToCollect`.
- **`afterCollection`**: try-catch — allows payer to reconcile state post-collection, cannot block (same gas exhaustion caveat). Called even when `tokensToCollect == 0` (zero-token collections still trigger reconciliation).

## Trust Relationships

### Payer → Collector

**Trust required**: The payer authorizes the collector contract and trusts it to enforce payment terms; that it will not collect more than the agreed-upon amounts per collection period.

**Mitigation**: The collector is a protocol-deployed contract with fixed logic. The escrow balance provides an absolute ceiling — the collector cannot extract more than the deposited balance.

> _RecurringCollector_: enforces per-agreement caps of `maxOngoingTokensPerSecond × maxSecondsPerCollection` (plus `maxInitialTokens` on first collection) per collection window. The payer's exposure is bounded by the agreement terms they signed or authorized.

### Payer → Receiver

**Trust required**: The receiver is paid immediately when collecting based on claimed work done. The payer relies on post-hoc enforcement rather than on-chain validation of the receiver's claims.

**Mitigation**: The payment protocol itself is agnostic to what evidence the receiver provides — that is the data service's domain.

> _SubgraphService_: the receiver submits a POI (Proof of Indexing) which is emitted in events but not validated on-chain. Payment proceeds regardless of POI correctness. The dispute system provides post-hoc enforcement: fishermen can challenge invalid POIs, and the indexer's locked stake (`tokensCollected × stakeToFeesRatio`) serves as economic collateral during the dispute period.
>
> _RAM as payer_: the payer is the protocol itself, and if configured, an eligibility oracle gates the receiver's ability to collect (checked by RecurringCollector via `IProviderEligibility`).

### Receiver → Payer

**Trust minimised by escrow**: The escrow is the primary trust-minimisation mechanism — to avoid trust in the payer, the receiver should bound uncollected work to what the escrow guarantees rather than relying on the payer to top up.

Caveats on effective escrow (contract payers introduce additional trust requirements — see caveat 3):

1. **Thawing reduces effective balance** — a payer can initiate a thaw; once the thaw period completes, those tokens are withdrawable. The receiver should account for the thawing period and any in-progress thaws when assessing available escrow.
2. **Cancellation freezes the collection window** at `canceledAt` — the receiver can still collect for the period up to cancellation (with `minSecondsPerCollection` bypassed), but no further.
3. **Contract payers can block** — if the payer is a contract that implements `IProviderEligibility`, it can deny collection via `isEligible` (see [RecurringCollector Extensions](#recurringcollector-extensions)).

**Mitigation**: The thawing period provides a window for the receiver to collect before funds are withdrawn. The escrow balance and thaw state are publicly visible on-chain.

> _RAM as payer_: RAM automates escrow maintenance (Full/OnDemand/JIT modes). When not operating in Full escrow mode, the receiver also depends on RAM's ability to fund at collection time. Mitigation: RAM is a protocol-deployed contract — its funding logic is transparent and predictable, with no adversarial incentive to deny payment.

### Receiver → Data Service

**Trust required**: The receiver (or their operator) calls the data service's `collect()` directly. The receiver trusts it to:

1. **Compute amounts correctly** — the data service determines its claim of what is earned
2. **Not be paused** — the data service may have a pause mechanism that would block collection

**Mitigation**: The data service is a protocol-deployed contract. Token amounts are capped by the collector independently, so data service overstatement is bounded.

> _SubgraphService_: `_tokensToCollect` computes the amount earned. The `enforceService` modifier requires the caller to be authorized by the receiver (indexer) for their provision.

### Receiver → Escrow

**Trust required**: The receiver trusts escrow to release funds when a valid collection is presented. The receiver has no direct access to escrow — funds can only flow through the authorized collection path (data service → collector → escrow → GraphPayments → receiver).

**Mitigation**: Escrow is a stateless intermediary — it debits the payer's balance and forwards to GraphPayments. No discretionary logic. The failure modes are insufficient balance or protocol-wide pause (escrow's `collect` has a `notPaused` modifier).

### Data Service → Collector

**Trust required**: The data service trusts the collector to faithfully enforce temporal and amount-based caps. The data service provides its own token calculation, but the collector applies `min(requested, cap)` — the data service relies on this capping being correct.

**Mitigation**: Both are protocol-deployed contracts. The two-layer capping model means neither layer alone determines the payout — the minimum of both applies.

### Collector → Data Service

**Trust required**: The collector trusts the data service to call `collect()` only with valid, legitimate payment requests. The collector validates payment terms but relies on the data service to verify service delivery.

**Mitigation**: The collector validates its own domain (agreement existence, temporal bounds, amount caps) independently.

> _RecurringCollector + SubgraphService_: the collector validates RCA terms; the data service verifies allocation status and emits POIs for dispute.

## Who Can Block Collection?

Which actors can prevent a collection from succeeding, and how:

| Actor        | Can block? | How (general model)                            |
| ------------ | ---------- | ---------------------------------------------- |
| Payer        | Yes        | Contract payer only, via `isEligible`          |
| Collector    | Yes        | Reject payment request based on its own rules  |
| Data service | Yes        | Pause mechanism; code-level revert conditions  |
| Receiver     | No         | Can only initiate, not block                   |
| Escrow       | Yes        | Insufficient balance; also protocol-wide pause |

### Implementation-Specific Notes

**ECDSA-signed agreements** (external payer): the payer is an EOA and has no on-chain blocking mechanism. The receiver's trust is bounded by the current escrow balance (minus any thawing amount).

**RAM-managed agreements** (protocol payer): the payer (RAM) has no adversarial incentive to block. If an eligibility oracle is configured, blocking trust effectively transfers to the oracle (see [RecurringCollector Extensions](#recurringcollector-extensions)).

## Trust Reduction Mechanisms

| Mechanism                                                       | What it bounds                                                     | Actor protected | Scope                    |
| --------------------------------------------------------------- | ------------------------------------------------------------------ | --------------- | ------------------------ |
| Escrow deposit + thaw period                                    | Payer can't instantly withdraw                                     | Receiver        | General                  |
| Two-layer token capping                                         | Neither data service nor collector alone sets amount               | Payer           | General                  |
| Collector-enforced agreement terms                              | Per-collection exposure                                            | Payer           | General                  |
| Cancellation still allows final collection                      | Receiver collects accrued amount                                   | Receiver        | General                  |
| Dispute system + stake locking                                  | Invalid POIs are challengeable                                     | Payer / network | SubgraphService          |
| Eligibility oracle                                              | Ineligible receivers denied                                        | Payer           | RecurringCollector + RAM |
| `lastCollectionAt` advancing only through validated collections | No fake liveness signals (advances even on zero-token collections) | All             | RecurringCollector       |

## Related Documents

- [MaxSecondsPerCollectionCap.md](../packages/horizon/contracts/payments/collectors/MaxSecondsPerCollectionCap.md) — Two-layer capping semantics
- [RecurringAgreementManager.md](../packages/issuance/contracts/agreement/RecurringAgreementManager.md) — RAM escrow management
- [RewardsEligibilityOracle.md](../packages/issuance/contracts/eligibility/RewardsEligibilityOracle.md) — Oracle trust model and failsafe
- [RewardAccountingSafety.md](./RewardAccountingSafety.md) — Reward accounting invariants
- [RewardConditions.md](./RewardConditions.md) — Reclaim conditions
