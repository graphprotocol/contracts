# EscrowRouter

## Purpose

Thin routing layer implementing `IPaymentsEscrow`. Registered as "PaymentsEscrow" in the Controller so all contracts (via GraphDirectory) get this as their escrow reference. Provides standard escrow for physical flows and delegates to overrides (IS virtual escrow) for IS-backed payers.

## Location

`packages/horizon/contracts/payments/EscrowRouter.sol`

## Design

**Standard escrow (default)**: Identical to PaymentsEscrow — has its own `escrowAccounts` storage, handles deposit/thaw/withdraw/collect using physical GRT.

**Override routing**: Governance-controlled `escrowOverrides[payer] → IPaymentsEscrow`. When set for a payer, `collect()` and `getBalance()` delegate to the override. Deposit/thaw/withdraw always use the router's own storage (overridden payers don't need physical deposits).

```
RC calls _graphPaymentsEscrow().collect(paymentType, payer, receiver, ...)
                    │
             ┌──────▼──────┐
             │ EscrowRouter │
             └──────┬──────┘
                    │
        escrowOverrides[payer] set?
           │                │
          yes               no
           │                │
    ┌──────▼──────┐  ┌─────▼────────────┐
    │ IS.collect() │  │ Standard escrow   │
    │ (virtual,    │  │ (own storage,     │
    │  mint GRT)   │  │  physical GRT)    │
    └──────────────┘  └──────────────────┘
```

## Key Details

- **Replaces PaymentsEscrow in Controller**: Not a wrapper — IS the escrow. Avoids msg.sender issues from forwarding.
- **Governor-controlled overrides**: `setEscrowOverride(payer, IPaymentsEscrow)` — only governor can set/remove.
- **Override receives same IPaymentsEscrow.collect() signature**: IS must implement this interface.
- **No changes to RC, SS, or IndexingAgreement**: Existing collect chain works unchanged.

## Open Questions

- **Escrow key mapping**: When IS receives `collect(paymentType, payer, receiver, tokens, ...)`, it needs to resolve `subgraphDeploymentID` from (payer, receiver). How IS resolves this is deferred — see [Status.md #4](../Status.md).
