# EscrowRouter

## Purpose

Route escrow operations to the correct backend: PaymentsEscrow (physical, for query fees) or IndexingSignal (virtual, for IS-backed indexing fees).

## Location

Does not exist yet.

## Design (from Design.md)

Governance-controlled override mapping: `escrowOverrides[payer] → address`. If set, delegate to override. Otherwise pass through to default PaymentsEscrow.

## Why It's Needed

RecurringCollector calls `_graphPaymentsEscrow().collect(...)` via immutable GraphDirectory. Without a router, there's no interception point to redirect IS-backed flows to IndexingSignal.

## Key Problem

The router pattern as described **cannot work transparently** because PaymentsEscrow.collect() and IndexingSignal.collect() have incompatible signatures. IS requires `subgraphDeploymentID` which the escrow interface doesn't carry.

## Options to Resolve

1. **Router with signature translation** — Router implements IPaymentsEscrow, translates to IS.collect() internally. Requires encoding subgraphDeploymentID in an existing parameter or a side-channel.
2. **IS implements IPaymentsEscrow** — IS exposes a PaymentsEscrow-compatible collect(). Internally maps (payer, receiver) back to (depositor, subgraph, indexer). Requires a lookup mapping.
3. **RecurringCollector calls IS directly** — Skip the router. RecurringCollector detects IS-backed agreements and calls IS.collect() instead of escrow. Requires RC changes.
4. **New collector for IS flows** — A dedicated collector (not RecurringCollector) that knows about IS and calls it directly. SubgraphService routes IS indexing fees to this collector.

## Open Questions

- Which option above? See [Status.md Needs Review #1](../Status.md).
- If router: what's the routing key? Payer alone may be ambiguous if same address has both query fee and IS-backed flows.
- How does `subgraphDeploymentID` reach IS through the escrow interface?
