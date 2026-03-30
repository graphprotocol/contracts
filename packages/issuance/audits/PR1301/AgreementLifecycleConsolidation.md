# Agreement Lifecycle Consolidation

Architectural refactor consolidating agreement lifecycle ownership into
RecurringCollector (RC), with SubgraphService (SS) and
RecurringAgreementManager (RAM) becoming reactive callback participants rather
than co-owners of lifecycle state.

## Problem: Fragmented Lifecycle Ownership

Previously, agreement lifecycle was split across three contracts with overlapping
responsibilities and increasingly tight coupling:

- **SS** exposed public entry points (`acceptIndexingAgreement`,
  `updateIndexingAgreement`, `cancelIndexingAgreementByPayer`) and orchestrated
  RC calls internally
- **RC** validated ECDSA signatures and stored acceptance state via a 4-value
  enum (`NotAccepted`, `Accepted`, `CanceledByServiceProvider`, `CanceledByPayer`)
- **RAM** authorized agreements via hash lookup (`approveAgreement`) and managed
  escrow in flat per-provider mappings

This meant state was scattered, the call graph was imperative (SS initiates → RC
records), and adding a new data service required replicating SS's lifecycle
methods.

Responding to audit findings within this fragmented architecture created a
compounding problem: each fix added duplicated validation logic across contracts,
introduced new edge cases at the seams, and tightened already-fragile coupling.
RAM and SS both approached Spurious Dragon bytecode limits, making further fixes
increasingly constrained. Consolidation was necessary to break this cycle —
moving lifecycle ownership to RC reduced total bytecode and relieved size pressure
on RAM and SS by eliminating duplicated orchestration code.

The tight coupling also limited future configuration and reuse — any new data
service or collector or agreement manager would have required reimplementing
the same entangled lifecycle logic.

## Solution: Collector-Driven Callbacks

RC becomes the **single state machine owner** for agreement lifecycle. SS and RAM
become **reactive participants** via well-defined callback interfaces.

### Responsibility Separation

| Concern               | Before                     | After                                   |
| --------------------- | -------------------------- | --------------------------------------- |
| Lifecycle entry point | SS public methods          | RC `offer()` / `accept()` / `cancel()`  |
| State model           | 4-value enum in RC         | `uint16` bitmask flags in RC            |
| Domain validation     | Inline in SS methods       | SS `acceptAgreement` callback           |
| Escrow management     | Flat maps in RAM           | Nested per-collector storage in RAM     |
| Authorization         | ECDSA + Authorizable in RC | Offer phase + collector whitelist in SS |
| State notifications   | None                       | `afterAgreementStateChange` callback    |

### New Interfaces

- **`IAgreementCollector`** — generic lifecycle operations and state flag
  constants. Decouples data services and agreement managers from RC-specific types.
- **`IAgreementStateChangeCallback`** — callback method for state transition
  notifications. Data services react to lifecycle events without blocking.
- **`IDataServiceAgreements`** (evolved) — extends the callback interface and
  adds `acceptAgreement` for domain-specific acceptance validation.

### Coupling Inversion

```
BEFORE (imperative):
  Caller → SS.acceptIndexingAgreement() → RC.accept(rca, sig)
  State split between SS (allocation binding) and RC (acceptance flag)

AFTER (callback-driven):
  Caller → RC.offer() → RC.accept()
    ↳ SS.acceptAgreement()   — validates allocation, stores collector ref
    ↳ SS.afterAgreementStateChange()  — domain-specific reaction (no-op here)
    ↳ RAM.afterAgreementStateChange() — escrow bookkeeping
  State owned by RC; SS and RAM derive what they need from callbacks
```

### State Model: Enum → Bitmask

The old 4-value enum could not express compound states (e.g., "accepted with
notice given by payer, auto-updated"). The new `uint16` bitmask uses independent
flags:

`REGISTERED` · `ACCEPTED` · `NOTICE_GIVEN` · `SETTLED` · `BY_PAYER` ·
`BY_PROVIDER` · `BY_DATA_SERVICE` · `UPDATE` · `AUTO_UPDATE` · `AUTO_UPDATED`

Composed states like `ACCEPTED | NOTICE_GIVEN | BY_PAYER` replace what would have
required additional enum values and transition logic.

### Callback Hardening

All callbacks are gas-capped at `MAX_CALLBACK_GAS` (1.5M) with non-reverting
semantics for state-change notifications. Failures emit `PayerCallbackFailed`
rather than propagating reverts. Callbacks to `msg.sender` are skipped (the caller
already has context), avoiding callback loops.

This incorporates audit findings TRST-H-1, L-1, H-2, H-4, SR-4 as integral
design rather than bolt-on mitigations.

### RAM Storage: Flat → Nested

```
BEFORE: mapping(agreementId => info)       — global, no collector scoping
AFTER:  mapping(collector => CollectorData)
          .agreements[agreementId]          — scoped per collector
          .providers[provider]              — pair-keyed escrow + agreement set
```

Enables multi-collector support and cleaner enumeration without cross-collector
interference.

### Additional Changes

- **RC upgradeability**: ERC-7201 namespaced storage, `initialize()` pattern,
  `TransparentUpgradeableProxy` deployment
- **RC pausability**: `PausableUpgradeable` with governor-managed pause guardians;
  `whenNotPaused` on `collect`, `offer`, `accept`, `cancel`
- **Drop EIP-712 signing from RC**: ECDSA validation removed; the two-phase
  offer/accept flow eliminates the need for on-chain signature verification
  since callers authenticate through normal `msg.sender` checks. Moving
  agreement state on-chain enables direct, atomic state transitions and
  eliminates the ambiguity of off-chain signed messages where unknown updates
  could exist — the on-chain state is always the complete, authoritative picture.
  This also improves the trust model: a contract payer that has submitted an
  offer has pre-approved it on-chain and cannot block acceptance, whereas the
  old signing model required the payer to cooperate at acceptance time.
- **Auto-update**: when a collection window expires and the provider has opted in
  (`AUTO_UPDATE` flag), RC automatically promotes pending terms — a lifecycle
  path only possible because RC owns the state machine. Data service callback
  reverts are caught so a failing callback cannot block the promotion.
- **Collector whitelist in SS**: `authorizedCollectors` mapping with
  `setAuthorizedCollector()` (owner-only) gates all callbacks via
  `_requireCollectorCaller()`, making SS collector-agnostic rather than
  hardcoded to a single RC instance

## Design Principles

1. **Single owner per concern** — RC owns lifecycle state, SS owns domain
   validation, RAM owns escrow accounting
2. **Callbacks over method calls** — loose coupling via interfaces; new data
   services implement callbacks without replicating lifecycle orchestration
3. **Compose state, don't enumerate it** — bitmask flags combine freely,
   eliminating combinatorial enum growth
4. **Fail-safe notifications** — gas-capped, non-reverting callbacks prevent
   one participant from blocking the state machine
5. **Collector-agnostic interfaces** — `IAgreementCollector` and callbacks use
   generic types (agreementId, state flags, opaque metadata); no collector-specific
   data is encoded into the interface, so data services and agreement managers
   can work with any conforming collector without adaptation

While the refactor moved significant code between contracts, the logic within
each contract is now more direct and easier to reason about. Each contract
has a single, well-defined role with clearer trust boundaries.
