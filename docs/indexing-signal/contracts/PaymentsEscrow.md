# PaymentsEscrow

## Purpose

Generic physical escrow for payment flows. Holds GRT in `(payer, collector, receiver)` accounts with deposit/thaw/withdraw lifecycle.

## Location

`packages/horizon/contracts/payments/PaymentsEscrow.sol`

## Key Design (existing, no changes planned)

- **Physical balances**: GRT deposited and held in contract
- **3-level mapping**: `escrowAccounts[payer][collector][receiver]`
- **collect()**: Deducts from balance, approves GraphPayments, delegates distribution
- **Thawing**: Withdrawal requires thaw period
- **Registered via GraphDirectory**: All contracts access it through `_graphPaymentsEscrow()`

## collect() Signature

```solidity
collect(PaymentTypes paymentType, address payer, address receiver,
        uint256 tokens, address dataService, uint256 dataServiceCut,
        address receiverDestination)
```

Note: `msg.sender` is the collector. No `subgraphDeploymentID` parameter.

## Relevance to IS

PaymentsEscrow is the existing escrow primitive. IS uses a virtual escrow model (no physical deposits). The integration challenge is making IS-backed flows pass through PaymentsEscrow's interface or bypass it cleanly.

## No Changes Planned

PaymentsEscrow should remain the generic physical escrow. IS integration should not modify it.
