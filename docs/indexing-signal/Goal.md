# Goal

## What

Direct protocol issuance toward indexing payments via IndexingSignal. Users lock GRT as signal, protocol mints proportional issuance, funds flow to indexers through RCAs.

## Done When

1. **Design complete** — all contracts have coherent, reviewed designs with no open disconnects
2. **Integration sound** — collection flow from SubgraphService through to IS mint-and-distribute works end-to-end
3. **Implementation clean** — contracts compile, match design, no dead code or stale patterns
4. **Tests pass** — unit tests cover key flows; integration tests verify cross-contract paths
5. **Docs current** — contract files in `docs/indexing-signal/contracts/` reflect actual implementation

## Quality Bar

- Issuance invariant holds: `RM_minted + IS_minted = issuancePerBlock * blocks`
- No double-minting, no uncounted minting
- Virtual escrow balances are always computable and consistent
- Collection flow respects GraphPayments distribution (protocol tax, data service cut, delegation pool, receiver)
- Existing payment flows (query fees via GraphTallyCollector) are unaffected

## Key Constraint

IndexingSignal piggybacks on RewardsManager's issuance rate with a shared denominator. This is the core mechanism — changes that break this invariant break everything.

## Navigation

- [Status.md](./Status.md) — current state, what needs review
- [Workflow.md](./Workflow.md) — how we iterate
- [Design.md](./Design.md) — high-level design
- [Disconnects.md](./Disconnects.md) — tracked gaps between design and implementation
- [contracts/](./contracts/) — per-contract details
