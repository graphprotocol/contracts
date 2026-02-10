# Indexing Signal

## Overview

Indexing Signal is a mechanism for directing protocol issuance toward indexing payments. Users lock GRT as signal for specific subgraph deployments, and the protocol mints new GRT proportional to that signal, funding Recurring Collection Agreements (RCAs) between signal depositors and indexers.

Indexing Signal is analogous to Curation Signal in its role of directing protocol issuance, but differs in where the issuance flows: curation issuance goes to indexer rewards (via RewardsManager), while indexing issuance goes to indexing payments (via RCAs).

## Reference Contracts

- **Curation**: `packages/contracts/contracts/curation/Curation.sol` - Pattern reference for signal mechanics
- **RewardsManager**: `packages/contracts/contracts/rewards/RewardsManager.sol` - Issuance rate source, signal-based reward distribution
- **PaymentsEscrow**: `packages/horizon/contracts/payments/PaymentsEscrow.sol` - Existing generic escrow primitive (payer→collector→receiver tuples); not modified
- **RecurringCollector**: `/git/graphprotocol/contracts/indexing-payments/packages/horizon/contracts/payments/collectors/RecurringCollector.sol` - RCA implementation (on indexing-payments branch)
- **GraphDirectory**: `packages/horizon/contracts/utilities/GraphDirectory.sol` - Protocol contract registry (singleton PaymentsEscrow registration)
- **IssuanceAllocator**: `packages/issuance/contracts/allocate/IssuanceAllocator.sol` - Issuance distribution to targets
- **SubgraphService**: `packages/subgraph-service/contracts/SubgraphService.sol` - Orchestrates collection flows

## Design Decisions

| Decision           | Choice                                  | Rationale                                                                                 |
| ------------------ | --------------------------------------- | ----------------------------------------------------------------------------------------- |
| Signal pricing     | 1:1 GRT to signal                       | Simpler than bonding curve; no early-mover advantage needed for indexing payments         |
| Deposit mechanism  | Lock with immediate withdraw            | Simple; thawing adds complexity without concrete requirement                              |
| Issuance source    | Self-minting, reads rate from RM        | Uses same per-signal issuance rate as RewardsManager                                      |
| Signal aggregation | RM reads both Curation + IndexingSignal | RewardsManager updated to query combined total signal                                     |
| Issuance split     | Global split                            | total_indexing_signal / total_signal determines IndexingSignal's share of issuance        |
| Escrow model       | Virtual (no physical deposits)          | IS computes balances from accumulators; GRT minted only on collect; no deposit/thaw/withdraw lifecycle |
| Escrow routing     | Router with governance-controlled overrides | Thin router in front of PaymentsEscrow; override mapping delegates IS-backed flows to IS  |
| Indexer count      | Depositor-chosen, protocol minimum      | Depositor sets desired count at deposit; protocol enforces minimum; privileged role exempt |
| Indexer count changes | Mutable over time                     | Depositor can increase/decrease indexer count and signal amount within constraints         |
| Indexer selection   | Off-chain                               | Selection performed off-chain; on-chain contract records and enforces the matched set     |
| Issuance per indexer | Equal split across set                 | Depositor's issuance divided equally among matched indexers (signal / N per indexer)      |
| RCA matching       | Automatic per depositor-indexer         | Protocol creates RCA entries for each depositor-indexer pair per subgraph                 |
| RCA acceptance     | Signed and offered off-chain            | RCA signed by payer-side, offered to indexer; indexer accepts by posting on-chain before deadline |
| RCA cancellation   | Out of scope for IS                     | IS responds to cancellation (settles uncollected issuance) but does not cause or control it |

## Architecture

### Signal and Issuance Flow

```
                    ┌──────────────────────────────┐
                    │   IssuanceAllocator           │
                    │   (allocates issuance/block)  │
                    └──────────────┬───────────────┘
                                   │
                         issuancePerBlock
                                   │
                    ┌──────────────▼───────────────┐
                    │      Total Signal             │
                    │  = curation + indexing signal  │
                    │  accRewardsPerSignal =         │
                    │  issuancePerBlock / totalSignal│
                    └──────┬───────────────┬───────┘
                           │               │
              ┌────────────▼──┐     ┌──────▼────────────┐
              │ Curation      │     │ Indexing Signal    │
              │ Signal        │     │                    │
              │ (bonding      │     │ (1:1 GRT,          │
              │  curve)       │     │  locked deposits)  │
              └──────┬────────┘     └──────┬─────────────┘
                     │                     │
        accPerSignal × curation   accPerSignal × indexing
                     │                     │
              ┌──────▼────────┐     ┌──────▼─────────────┐
              │ RewardsManager│     │ IndexingSignal      │
              │ mints rewards │     │ virtual escrow:     │
              │ → indexers    │     │ mint on collect     │
              └───────────────┘     └────────────────────┘
```

### Per-Signal Issuance Calculation

Both RewardsManager and IndexingSignal use the same accumulated rewards-per-signal rate:

```
accRewardsPerSignal += (issuancePerBlock × blocksDelta) / totalSignal

where totalSignal = totalCurationTokens + totalIndexingTokens
```

**RewardsManager** uses this to calculate per-subgraph indexer rewards:

```
subgraphRewards = accRewardsPerSignalDelta × subgraphCurationSignal
```

**IndexingSignal** uses this to calculate per-subgraph indexing issuance:

```
subgraphIssuance = accRewardsPerSignalDelta × subgraphIndexingSignal
```

This ensures: `RM_minted + IS_minted = issuancePerBlock × blocks` (total issuance preserved).

### Deposit and Signal Flow

```
User deposits GRT                  User withdraws signal
      │                                   │
      ▼                                   ▼
 ┌─────────────┐                   ┌──────────────────┐
 │ deposit()   │                   │ withdraw()       │
 │ Lock GRT    │                   │ Immediate return │
 │ 1:1 signal  │                   │ of GRT           │
 └──────┬──────┘                   │ Remove signal    │
        │                          │ Cancel RCAs      │
        ▼                          └──────────────────┘
 Signal active
 Issuance accrues
 RCAs auto-created
 with indexers
```

### Virtual Escrow Model

IndexingSignal acts as a virtual escrow — no GRT is physically deposited or held. Escrow "balances" are computed from IS accumulators and represent accumulated uncollected issuance. GRT is minted only at the moment of collection.

**Why virtual?** A physical escrow requires deposit/thaw/withdraw lifecycle management. Since issuance is protocol-minted (not user-deposited), physical deposits create unnecessary complexity: who is the payer? Who manages thaw? How are leftover funds reclaimed? Virtual escrow eliminates all of this.

**Escrow Router**: A thin governance-controlled router sits at the protocol's PaymentsEscrow address. For standard payment flows (query fees via GraphTallyCollector), it delegates to the existing PaymentsEscrow. For IS-backed flows (indexing payments via RecurringCollector), it delegates to IndexingSignal. Governance controls which overrides are approved.

```
                   ┌──────────────────────┐
                   │   Escrow Router       │
                   │   (governance-        │
                   │    controlled)        │
                   └──────┬───────┬───────┘
                          │       │
              default     │       │  override (payer-based)
                          ▼       ▼
              ┌───────────────┐  ┌──────────────────┐
              │ PaymentsEscrow│  │ IndexingSignal    │
              │ (physical,    │  │ (virtual escrow,  │
              │  standard)    │  │  mint-on-collect) │
              └───────────────┘  └──────────────────┘
```

**Virtual escrow operations:**
- `getBalance(depositor, collector, indexer)` → computed from accumulators (no storage read of a "balance" field)
- `collect(depositor, subgraph, indexer, amount)` → IS mints GRT, sends to GraphPayments for distribution
- No `deposit()`, `thaw()`, or `withdraw()` — balance is virtual, GRT only exists at collection time

### Collection Flow

```
Indexer calls SubgraphService.collect() for RCA
      │
      ▼
 ┌─────────────────────────────────────────────────┐
 │ SubgraphService                                 │
 │                                                 │
 │ 1. RecurringCollector validates RCA terms        │
 │                                                 │
 │ 2. Router delegates to IndexingSignal            │
 │    (governance-approved override for this payer) │
 │                                                 │
 │ 3. IS computes accumulated issuance since last   │
 │    collection for (depositor, subgraph, indexer) │
 │                                                 │
 │ 4. IS mints GRT (up to collection amount)        │
 │                                                 │
 │ 5. Minted GRT distributed via GraphPayments:     │
 │    protocol tax, data service cut, delegation    │
 │    pool, receiver (indexer)                      │
 │                                                 │
 │ 6. IS updates per-indexer collection snapshot     │
 └─────────────────────────────────────────────────┘
```

### RCA Cancellation Response

IS does not cause or control RCA cancellation — that is handled externally. When IS is notified that an RCA for (depositor, subgraph, indexer) has been cancelled:

1. IS updates the per-indexer collection snapshot to current accumulator value
2. Accumulated but uncollected issuance for that tuple is settled (never minted — it simply stops being collectible)
3. Signal remains active — new issuance continues accruing for whichever indexer is next assigned
4. If all indexers for a depositor are removed, issuance accrues but is not collectible until new indexers are assigned

### Indexer Set Matching

Each depositor chooses how many indexers they want for their signal position, subject to a protocol-enforced **minimum indexer count**. Indexers are selected off-chain and registered on-chain as the depositor's matched set. Issuance is split equally across the set.

A **privileged protocol role** can set an indexer count below the minimum (e.g., for protocol-managed positions or special cases).

Both the indexer count and signal amount can be adjusted over time by the depositor.

```
Protocol minimum indexer count = 3

Depositor A: 300 GRT signal, 3 indexers (meets minimum)
  → Indexer X: 1/3 issuance
  → Indexer Y: 1/3 issuance
  → Indexer Z: 1/3 issuance

Depositor B: 500 GRT signal, 5 indexers (above minimum, more redundancy)
  → Each of 5 indexers: 1/5 issuance

Privileged role: 100 GRT signal, 1 indexer (below minimum, permitted)
  → Indexer W: full issuance

Each RCA: depositor → RecurringCollector → indexer
  Signed by payer-side, offered to indexer off-chain
  Indexer accepts by posting on-chain before deadline
  maxOngoingTokensPerSecond = depositor's issuance rate / N
```

**Depositor Lifecycle:**

- **Deposit**: Depositor calls `deposit(subgraph, tokens, indexerCount)` specifying desired indexer count (must be at least `minimumIndexerCount` unless privileged)
- **Adjust indexer count**: Depositor can increase or decrease their count over time (still subject to minimum). Off-chain process selects/deselects indexers accordingly.
- **Adjust signal**: Depositor can add more GRT or withdraw to change signal amount. Issuance rate per indexer adjusts proportionally.
- **Indexer set registration**: Off-chain process selects indexers, calls `setDepositorIndexerSet(depositor, subgraph, indexers[])` on-chain
- **On set change**: Existing RCAs for removed indexers are cancelled (with final collection window); new RCAs created for added indexers
- **On signal withdrawal**: Depositor's RCAs with all matched indexers are cancelled

**Scaling:**

- RCA entries scale as O(depositors × depositorIndexerCount) per subgraph
- Each depositor's indexer count is bounded, so scaling is O(depositors × N_i) where N_i is per-depositor
- Gas cost per depositor is predictable since their N is known

## Contract: IndexingSignal

### Location

`packages/issuance/contracts/signal/IndexingSignal.sol`

### Storage

```solidity
struct SignalPool {
    uint256 totalTokens;           // Total GRT locked as signal for this subgraph
    uint256 accIssuancePerSignal;   // Accumulated issuance per signal unit (snapshot)
    uint256 accIssuancePerSignalSnapshot; // Snapshot of global accumulator
    uint256 accIssuanceForSubgraph; // Total accumulated issuance for this subgraph
}

struct DepositorPosition {
    uint256 tokens;                // GRT locked by this depositor for this subgraph
    uint256 accIssuanceSnapshot;   // Snapshot for calculating pending issuance
    uint256 indexerCount;          // Depositor's desired number of indexers
    address[] indexerSet;          // Current matched indexer set (selected off-chain)
}

// Global state
uint256 public accIssuancePerSignal;           // Global accumulator
uint256 public accIssuancePerSignalLastBlock;   // Block of last update
uint256 public totalIndexingSignal;             // Total GRT locked across all subgraphs
uint256 public minimumIndexerCount;             // Protocol-enforced minimum (e.g., 3)

// Per-subgraph
mapping(bytes32 => SignalPool) public pools;

// Per-depositor per-subgraph
mapping(address => mapping(bytes32 => DepositorPosition)) public positions;

// Privileged role that can bypass minimumIndexerCount
mapping(address => bool) public privilegedSignalers;
```

### Key Functions

```solidity
// --- Signal Management ---

/// Lock GRT as indexing signal for a subgraph deployment.
/// indexerCount must be >= minimumIndexerCount (unless caller is privileged).
function deposit(bytes32 subgraphDeploymentID, uint256 tokens, uint256 indexerCount) external;

/// Add more GRT to an existing signal position
function addSignal(bytes32 subgraphDeploymentID, uint256 tokens) external;

/// Withdraw GRT from a signal position (immediate)
function withdraw(bytes32 subgraphDeploymentID, uint256 tokens) external;

/// Change the desired indexer count for an existing position.
/// Must be >= minimumIndexerCount (unless caller is privileged).
/// Triggers off-chain re-selection of indexer set.
function setIndexerCount(bytes32 subgraphDeploymentID, uint256 indexerCount) external;

// --- Indexer Set Management ---

/// Set the protocol-wide minimum indexer count (governance only)
function setMinimumIndexerCount(uint256 count) external;

/// Grant/revoke privileged signaler status (governance only).
/// Privileged signalers can set indexerCount below the minimum.
function setPrivilegedSignaler(address account, bool privileged) external;

/// Register the matched indexer set for a depositor's position (authorized off-chain role).
/// indexers.length must equal the depositor's indexerCount.
/// Creates RCAs for added indexers, cancels RCAs for removed indexers.
function setDepositorIndexerSet(
  address depositor,
  bytes32 subgraphDeploymentID,
  address[] calldata indexers
) external;

// --- Issuance ---

/// Collect issuance for a depositor-subgraph-indexer tuple.
/// Computes accumulated virtual balance, mints GRT, distributes via GraphPayments.
/// Called during RCA collection flow (via escrow router delegation).
function collect(
  address depositor,
  bytes32 subgraphDeploymentID,
  address indexer,
  uint256 amount
) external returns (uint256 collectedTokens);

/// Get the virtual escrow balance for a depositor-subgraph-indexer tuple.
/// Computed from accumulators — no physical balance exists.
function getVirtualBalance(
  address depositor,
  bytes32 subgraphDeploymentID,
  address indexer
) external view returns (uint256);

/// Update the global issuance accumulator
function updateAccIssuancePerSignal() public;

/// Hook called when signal changes (analogous to RM.onSubgraphSignalUpdate)
function onSignalUpdate(bytes32 subgraphDeploymentID) internal;

// --- Views ---

/// Get total indexing signal for a subgraph
function getSubgraphSignal(bytes32 subgraphDeploymentID) external view returns (uint256);

/// Get a depositor's position for a subgraph
function getDepositorPosition(
  address depositor,
  bytes32 subgraphDeploymentID
) external view returns (DepositorPosition memory);

/// Get pending (unminted) issuance for a depositor-subgraph pair (total across all indexers)
function getPendingIssuance(address depositor, bytes32 subgraphDeploymentID) external view returns (uint256);

/// Get pending issuance for a specific depositor-indexer pair (1/N of total)
function getPendingIssuanceForIndexer(
  address depositor,
  bytes32 subgraphDeploymentID,
  address indexer
) external view returns (uint256);

/// Get total indexing signal across all subgraphs
function getTotalSignal() external view returns (uint256);
```

### Issuance Calculation

IndexingSignal reads the issuance rate from RewardsManager and calculates its share:

```solidity
function _getNewIssuancePerSignal() internal view returns (uint256) {
  uint256 blocksDelta = block.number - accIssuancePerSignalLastBlock;
  if (blocksDelta == 0) return 0;

  uint256 issuancePerBlock = rewardsManager.getAllocatedIssuancePerBlock();

  // Total signal = curation tokens + indexing tokens
  uint256 curationTokens = graphToken.balanceOf(address(curation));
  uint256 totalSignal = curationTokens + totalIndexingSignal;
  if (totalSignal == 0) return 0;

  // Issuance accrued per unit of signal
  return (issuancePerBlock * blocksDelta * FIXED_POINT_SCALING) / totalSignal;
}
```

Per-depositor pending issuance (total, before indexer split):

```solidity
function _getPendingIssuance(address depositor, bytes32 subgraphDeploymentID) internal view returns (uint256) {
  DepositorPosition storage pos = positions[depositor][subgraphDeploymentID];
  uint256 currentAccPerSignal = accIssuancePerSignal + _getNewIssuancePerSignal();
  uint256 delta = currentAccPerSignal - pos.accIssuanceSnapshot;
  return (pos.tokens * delta) / FIXED_POINT_SCALING;
}
```

Per-indexer issuance (equal split across depositor's matched set):

```solidity
function _getPendingIssuanceForIndexer(
  address depositor,
  bytes32 subgraphDeploymentID,
  address indexer
) internal view returns (uint256) {
  DepositorPosition storage pos = positions[depositor][subgraphDeploymentID];
  require(_isInIndexerSet(pos, indexer), "Indexer not in depositor's matched set");

  uint256 totalIssuance = _getPendingIssuance(depositor, subgraphDeploymentID);
  uint256 n = pos.indexerSet.length;
  return totalIssuance / n; // Equal split; remainder handled on last collection
}
```

## Contract Changes: RewardsManager

### Total Signal Calculation

RewardsManager must be updated to read combined signal:

```solidity
function _getTotalSignal() internal view returns (uint256) {
  uint256 curationTokens = graphToken().balanceOf(address(curation()));
  uint256 indexingTokens = indexingSignal.getTotalSignal();
  return curationTokens + indexingTokens;
}
```

This replaces the current `graphToken().balanceOf(address(curation()))` calls.

### Per-Subgraph Signal

When calculating per-subgraph rewards, RM continues to use only curation signal for its own reward distribution. The accRewardsPerSignal rate is shared (uses total signal as denominator), but RM multiplies by curation signal only:

```solidity
// In _getSubgraphRewardsState():
uint256 subgraphSignal = curation().getCurationPoolTokens(_subgraphDeploymentID);
// NOT: subgraphSignal = curationSignal + indexingSignal (that would double-count)
```

### New State

```solidity
IIndexingSignal public indexingSignal; // Reference to IndexingSignal contract
```

### New Functions

```solidity
function setIndexingSignal(address _indexingSignal) external onlyGovernor;
```

## Contract: Escrow Router

### Purpose

A thin governance-controlled proxy that sits at the protocol's PaymentsEscrow address (or alongside it). Routes escrow operations to the appropriate backend based on a governance-controlled override mapping.

### Design

```solidity
// Governance-controlled override: payer → escrow implementation
// When set, all escrow operations for this payer delegate to the override.
// Zero address = use default PaymentsEscrow.
mapping(address payer => address override) public escrowOverrides;

// Default escrow (the existing PaymentsEscrow singleton)
IPaymentsEscrow public defaultEscrow;
```

**Routing logic**: For `collect()`, `getBalance()`, etc. — check `escrowOverrides[payer]`. If set, delegate to override. Otherwise, pass through to `defaultEscrow`.

**Open question**: Payer alone may be insufficient if the same address uses both standard escrow (query fees) and virtual escrow (indexing payments). May need `(payer, collector)` as the routing key, or the override implementation itself distinguishes based on the collector parameter.

### Governance

- Only governance can set/remove overrides
- Provides protocol-level control over which escrow implementations are active
- Existing PaymentsEscrow remains untouched as the generic primitive

## Contract Changes: SubgraphService

### Collection Flow

SubgraphService collection for indexing RCAs goes through the standard escrow router path. The router detects the override and delegates to IndexingSignal, which computes the virtual balance, mints, and distributes.

### RCA Cancellation

When an RCA is cancelled (externally triggered), SubgraphService or the cancellation mechanism notifies IndexingSignal to settle the uncollected issuance for that (depositor, subgraph, indexer) tuple.

## Open Questions and Future Considerations

### Escrow Router

- Is payer the right routing key? If the same address uses both standard escrow and virtual escrow (e.g., query fees + indexing payments), payer alone is ambiguous. May need `(payer, collector)` as the key.
- Should the router be a new contract registered in the Controller, or a wrapper deployed alongside PaymentsEscrow?
- How does the override get set for new depositors? Governance-managed allowlist, or automatic based on IS position?

### Per-Indexer Collection Tracking

- Current IS accumulator model tracks issuance per-depositor. Virtual escrow needs per-(depositor, subgraph, indexer) collection snapshots to know how much each indexer has already collected.
- This requires additional storage: per-indexer collection snapshot mapping.
- When an indexer is removed from a set, their snapshot is settled. When re-added later, their snapshot resets to current.

### RCA Cancellation Settlement

- What happens to accumulated but uncollected issuance when an RCA is cancelled? Options:
  - Never minted (simplest — issuance simply doesn't happen)
  - Minted and sent to a reclaim address (mirrors RM's reclaim pattern)
- Who triggers the cancellation notification to IS? SubgraphService, RecurringCollector, or an external process?

### Indexer Set Management

- Who is authorized to call `setDepositorIndexerSet()`? A dedicated off-chain operator role, or governance multisig?
- What happens when not enough indexers are available to fill a depositor's requested count?
- Should there be a minimum stake/allocation requirement for indexers to be eligible for selection?
- How frequently can the set be rotated? Should there be a cooldown to prevent disruption?
- Rounding remainder when dividing issuance by N: accumulate dust or distribute to last indexer?

### RCA Term Derivation

- How are RCA `maxOngoingTokensPerSecond` values calculated from signal and issuance rate?
- Should terms update dynamically as signal proportions change, or be fixed at RCA creation?
- When the indexer set changes, how are RCA terms for the new set derived?

### Gas Optimization

- Lazy RCA creation (create on first collect) vs eager (create on signal/allocation change)
- Batched minting for multiple depositors in a single collect transaction
- Consider a maximum number of depositors per subgraph or pagination

### Signal Depositor Incentives

- Depositors lock GRT and direct issuance to indexers. What is the depositor's incentive?
- Possible: depositors are dApp operators who want reliable indexing for their subgraphs
- Possible: depositors receive a portion of query fees from the indexers they fund

### Edge Cases

- Handling rounding errors in per-depositor issuance calculations
- Minimum signal deposit to prevent dust attacks
- Denied subgraphs: should IndexingSignal respect the RM denylist?
- What if an indexer in the set closes their allocation? Remove from set, or let off-chain process handle rotation?

### Relationship to Existing Issuance Infrastructure

- IndexingSignal needs to be a GraphTokenMinter to self-mint GRT
- Coordination with IssuanceAllocator if issuance rates change
- Ensuring RM and IndexingSignal don't both count the same signal (double-mint)
