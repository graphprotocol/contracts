# RecurringAgreementManager

RCA-based payments require escrow pre-deposits — the payer must hold enough escrow to cover the maximum that could be collected in the next collection window. RecurringAgreementManager (RAM) is the payer for protocol-escrowed agreements: it receives minted GRT from the IssuanceAllocator and keeps each provider's escrow funded to cover worst-case collection amounts, with no manual top-ups in the normal path.

RAM is collector-agnostic: it supports any collector implementing `IAgreementCollector`, including collectors with different pricing models and agreement types. RecurringCollector (RC) is the only collector today and is used as the concrete example throughout.

One escrow account per (RAM, collector, provider) tuple covers **all** managed agreements for that (collector, provider) pair, so multiple agreements share a single balance. Fully funded (the Full basis target) means:

```
sum(maxNextClaim for all active agreements for that pair) <= PaymentsEscrow.escrowAccounts[RAM][collector][provider]
```

Lower bases (and automatic degradation) hold less than this; the `beforeCollection` JIT top-up covers any gap at collection time. See [Escrow Behavior](#escrow-behavior).

**Funding is not guaranteed by the contract.** RAM can only pay from the GRT it holds, so coverage is bounded by issuance inflow. If issuance doesn't keep pace with committed `maxNextClaim`, escrow degrades and the JIT top-up can run dry — a collection may then under-pay or revert. The contract enforces no cap on commitments: keeping them within fundable limits is the responsibility of the `AGREEMENT_MANAGER_ROLE` (which creates obligations via `offerAgreement`) together with the operator's basis and issuance configuration.

It implements eight interfaces:

- **`IIssuanceTarget`** — receives minted GRT from IssuanceAllocator
- **`IAgreementOwner`** — receives the collection callbacks (`beforeCollection` / `afterCollection`); RAM advertises support via ERC-165 to act as a contract payer
- **`IRecurringAgreementManagement`** — agreement lifecycle: offer, cancel, force-remove, reconcile (per-agreement and per-provider)
- **`IRecurringEscrowManagement`** — escrow configuration: basis, thresholds, thaw fraction, residual factor
- **`IProviderEligibilityManagement`** — eligibility oracle configuration
- **`IRecurringAgreements`** — read-only queries: agreement info, escrow state, global tracking
- **`IProviderEligibility`** — delegates payment eligibility checks to an optional oracle
- **`IEmergencyRoleControl`** — pause-guardian escape hatch: `emergencyRevokeRole` (cannot revoke `GOVERNOR_ROLE`)

## Roles

- **GOVERNOR_ROLE** — sets issuance allocator and eligibility oracle; grants `DATA_SERVICE_ROLE`, `COLLECTOR_ROLE`, and other roles; admin of `OPERATOR_ROLE`
- **OPERATOR_ROLE** — sets escrow basis, thresholds/margin, thaw fraction, and residual factor; `forceRemoveAgreement`; admin of `AGREEMENT_MANAGER_ROLE`
  - **AGREEMENT_MANAGER_ROLE** — offers agreements/updates, cancels agreements
- **PAUSE_ROLE** — pauses the contract; `emergencyClearEligibilityOracle`; `emergencyRevokeRole` (any role except `GOVERNOR_ROLE`)
- **Permissionless** — `reconcileAgreement`, `reconcileProvider`, and the `RecurringAgreementHelper` batch wrappers (`reconcile`, `reconcileCollector`, `reconcileAll`)

`DATA_SERVICE_ROLE` and `COLLECTOR_ROLE` gate which data services and collectors may appear in offered agreements. Role changes are not retroactive: revoking a role does not invalidate already-tracked agreements — they still reconcile and settle — it only gates _new_ offers and first-time discovery.

When paused, all permissionless state-changing operations are blocked, including the collection callbacks and reconciliation. Operator-gated functions (configuration setters, `forceRemoveAgreement`) remain callable.

## Agreement Lifecycle

### Offer → Accept

1. **Offer.** The agreement manager calls `offerAgreement(collector, offerType, offerData)`. RAM forwards the opaque offer to the collector (new agreement or update), validates the returned details (payer is RAM, data service holds `DATA_SERVICE_ROLE`, non-zero agreement ID and provider), registers the agreement under its (collector, provider) pair, then reconciles its escrow. Requires `AGREEMENT_MANAGER_ROLE`.
2. **Accept.** Acceptance happens on the collector via the data service: the service provider accepts through the data service (e.g. SubgraphService), which calls `RecurringCollector.accept(...)` — the collector requires the caller to be the agreement's data service. No payer signature is needed; RAM's on-chain offer from step 1 is the authorization (it replaces the ECDSA signature a wallet payer would provide). RAM is not involved here; it picks up the accepted state on the next reconciliation.

### Collect → Reconcile

Collection flows `SubgraphService → RecurringCollector → PaymentsEscrow`. The collector then calls back into RAM:

- **`beforeCollection`** — just-in-time top-up. If escrow can't cover the pending collection, RAM deposits the shortfall (funds permitting). This safety net is always active regardless of escrow basis.
- **`afterCollection`** — reconciles the agreement and rebalances its pair's escrow in the same transaction.

If RAM is paused, these callbacks revert (low-level calls, so the collection itself still succeeds) and escrow accounting drifts until RAM is unpaused and reconciled. To fully halt collections, pause `RecurringCollector` too.

Reconciliation can also be triggered manually at any time (permissionless):

- **`reconcileAgreement(collector, agreementId)`** — re-reads one agreement's `maxNextClaim` from the collector and rebalances its pair's escrow (gas-predictable).
- **`reconcileProvider(collector, provider)`** — rebalances one pair's escrow and runs cleanup (O(1)).
- Batch wrappers **`reconcile`**, **`reconcileCollector`**, **`reconcileAll`** live in the stateless `RecurringAgreementHelper`, which loops over agreements and delegates each call back to RAM.

### Cancel / Remove

- **`cancelAgreement(collector, agreementId, versionHash, options)`** — routes cancellation through the collector, then reconciles. Depending on `versionHash`, cancels an un-accepted offer, an accepted agreement, or a pending update. Requires `AGREEMENT_MANAGER_ROLE`.
- **`forceRemoveAgreement(collector, agreementId)`** — operator escape hatch for agreements whose collector is unresponsive (broken upgrade, permanent pause). Drops the agreement and rebalances the pair. Requires `OPERATOR_ROLE`.

### Cleanup

An agreement is deleted automatically once its `maxNextClaim` reaches 0, observed at the next reconcile. The trigger is uniform; only the timing differs by state:

| State                     | `maxNextClaim` reaches 0              |
| ------------------------- | ------------------------------------- |
| CanceledByServiceProvider | Immediately                           |
| CanceledByPayer           | After collection window expires       |
| Accepted past endsAt      | After final collection window expires |
| NotAccepted (expired)     | After `rca.deadline` passes           |

When a (collector, provider) pair has no agreements left and its escrow balance falls below a small residual threshold (`2^minResidualEscrowFactor`, default ≈ 0.001 GRT), the pair — and the collector, if it has no pairs left — is dropped from tracking to avoid wasting gas on dust. Residual funds remain in PaymentsEscrow; a later offer for the same pair re-adds tracking automatically.

## Escrow Behavior

`EscrowBasis` (operator-set) controls how aggressively escrow is pre-funded. It is a **maximum aspiration**: when RAM lacks the balance to sustain it, the effective basis automatically degrades, then recovers as balance returns. The `beforeCollection` JIT top-up backstops any gap regardless of basis.

Two distinct things move the basis. The operator can raise or lower the **configured** ceiling at any time via `setEscrowBasis` (e.g. drop to OnDemand or JustInTime to stop pre-funding). Independently, automatic degradation lowers only the **effective** basis when spare balance is short, never the configured value — so the configured ceiling is restored automatically once balance recovers.

```
enum EscrowBasis { JustInTime, OnDemand, Full }
```

| Level          | Deposit floor     | Thaw ceiling      | Behavior                                      |
| -------------- | ----------------- | ----------------- | --------------------------------------------- |
| Full (default) | `sumMaxNextClaim` | `sumMaxNextClaim` | Pre-deposits worst-case for all agreements.   |
| OnDemand       | 0                 | `sumMaxNextClaim` | No new deposits; holds existing escrow.       |
| JustInTime     | 0                 | 0                 | Thaws everything; pure pay-as-you-go via JIT. |

(`sumMaxNextClaim` is the per-pair sum.)

### Automatic degradation

RAM compares its **spare** balance (token balance minus the total amount already owed to escrow) against its aggregate `sumMaxNextClaim` — the sum across every pair it tracks. As spare shrinks, the effective basis degrades from the configured ceiling through these states (shown for the default Full configuration; a lower ceiling simply starts further down):

| Effective state | Condition on spare     | Result                                    |
| --------------- | ---------------------- | ----------------------------------------- |
| Full            | ~1.06× claims < spare  | Pre-deposit and hold at `sumMaxNextClaim` |
| OnDemand        | ~0.5× < spare ≤ ~1.06× | No new deposits, but hold existing escrow |
| JIT             | spare ≤ ~0.5× claims   | Thaw everything; rely on JIT top-ups      |

The two thresholds are operator-tunable (`minOnDemandBasisThreshold`, default 50%; `minFullBasisMargin`, default ~6% headroom above 100%). The deposit gate is stricter than the hold gate, so escrow degrades and recovers smoothly rather than oscillating.

**Operator caution — offers can trigger instant degradation.** `offerAgreement` raises `sumMaxNextClaim` without checking whether RAM can still fund the current basis. A single offer can push spare below a threshold and degrade the effective basis for **all** pairs at once — existing fully-escrowed providers silently lose their proactive deposits. Verify escrow headroom before offering. (An on-chain guard was considered but dropped for contract-size reasons.)

## Max Next Claim

`maxNextClaim` is the worst-case amount collectable in the next window. For accepted agreements it comes from `RecurringCollector.getMaxNextClaim(agreementId)` (single source of truth); for a pre-accepted offer it is a conservative estimate:

```
maxNextClaim = maxOngoingTokensPerSecond * maxSecondsPerCollection + maxInitialTokens
```

| Agreement State             | maxNextClaim                                                         |
| --------------------------- | -------------------------------------------------------------------- |
| NotAccepted (pre-offered)   | Stored estimate from `offerAgreement`                                |
| NotAccepted (past deadline) | 0 (expired offer, removable)                                         |
| Accepted, never collected   | Calculated by RecurringCollector (initial + ongoing)                 |
| Accepted, after collect     | Calculated by RecurringCollector (ongoing only)                      |
| CanceledByPayer             | Calculated by RecurringCollector (window capped at collectableUntil) |
| CanceledByServiceProvider   | 0                                                                    |
| Fully expired               | 0                                                                    |

## Monitoring

Read-only views (on RAM via `IRecurringAgreements`, plus richer aggregates on `RecurringAgreementHelper`):

- **Escrow** — `getEscrowAccount(collector, provider)` exposes the live PaymentsEscrow account (balance, thawing, thaw end).
- **Claims** — `getSumMaxNextClaim()` (global), `getSumMaxNextClaim(collector, provider)` (pair), `getAgreementMaxNextClaim(collector, agreementId)`, `getTotalEscrowDeficit()` (unfunded amount across all pairs).
- **Enumeration** — collector/provider/agreement counts and indexed accessors; `getAgreementInfo`, `getEscrowBasis`, and the tuning parameters.
- **Helper audits** — `auditGlobal`, `auditProviders`, `auditProvider`, and `checkStaleness` (compares cached vs. live `maxNextClaim` and snapshot vs. live escrow).

Events worth watching: `AgreementAdded` / `AgreementReconciled` / `AgreementRemoved`, `AgreementRejected` (with reason), `EscrowFunded` / `EscrowWithdrawn`, and **`DistributeIssuanceFailed`** — emitted when the allocator reverts during a pull (collection continues without fresh issuance; a healthy allocator should never emit this).

## Configuration

| Setter                               | Role     | Effect                                                                                           |
| ------------------------------------ | -------- | ------------------------------------------------------------------------------------------------ |
| `setIssuanceAllocator(addr)`         | Governor | Source of minted GRT. ERC165-validated; `address(0)` disables issuance pulls.                    |
| `setProviderEligibilityOracle(addr)` | Governor | Optional oracle; `address(0)` means all providers eligible.                                      |
| `setEscrowBasis(basis)`              | Operator | Maximum escrow aspiration (Full / OnDemand / JustInTime).                                        |
| `setMinOnDemandBasisThreshold(u8)`   | Operator | Spare-balance gate for holding escrow (default 128 = 50%).                                       |
| `setMinFullBasisMargin(u8)`          | Operator | Headroom gate for proactive deposits (default 16 ≈ 6%).                                          |
| `setMinThawFraction(u8)`             | Operator | Ignore thaws below this fraction of a pair's claims (default 16 ≈ 6%; anti micro-thaw griefing). |
| `setMinResidualEscrowFactor(u8)`     | Operator | Dust threshold (`2^value`) below which an empty pair is dropped (default 50 ≈ 0.001 GRT).        |

## Deployment

Prerequisites: GraphToken, PaymentsEscrow, RecurringCollector, IssuanceAllocator deployed.

1. Deploy RecurringAgreementManager implementation (graphToken, paymentsEscrow)
2. Deploy TransparentUpgradeableProxy with implementation and initialization data
3. Initialize with governor address
4. Grant `OPERATOR_ROLE` to the operator account
5. Operator grants `AGREEMENT_MANAGER_ROLE` to the agreement manager account
6. Configure IssuanceAllocator to allocate tokens to RecurringAgreementManager

## Key Concepts

A few design ideas that make the behavior above easier to reason about. For function- and field-level detail, see the NatSpec on the contract.

- **Min/max escrow targets.** Each rebalance derives a `(min, max)` band from the effective basis rather than a single target: deposit below `min`, thaw above `max`. Because `min <= max` always holds, and degradation drops `min` to 0 while `max` holds at the claim level, escrow settles smoothly instead of oscillating. Within the band, an active thaw timer is never reset.

- **Spare-balance accounting.** Degradation decisions use `spare = balance − totalEscrowDeficit`, where `totalEscrowDeficit` is the sum of each pair's unfunded amount (`max(0, claims − escrowed)`). Tracking it per-pair means an over-funded pair can't mask another's shortfall. Snapshots are an accounting input, not a live balance — they can drift between reconciliations until the next rebalance resyncs them.

- **Issuance freshness.** Before any balance-dependent decision RAM pulls issuance so its token balance is current, with a per-block guard so the two collection callbacks don't pull twice in one transaction. A reverting allocator is tolerated (surfaced via `DistributeIssuanceFailed`) rather than blocking payments.
