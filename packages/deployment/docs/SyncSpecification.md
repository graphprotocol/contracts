# Sync Specification

This document defines the bidirectional sync behavior between address books and rocketh deployment records.

## Data Structures

### Address Book Entry (Proxied Contract)

```json
{
  "ContractName": {
    "address": "0x...", // Proxy address
    "proxy": "graph|transparent",
    "proxyAdmin": "0x...", // Inline or via separate entry
    "implementation": "0x...", // Current on-chain implementation
    "implementationDeployment": {
      "txHash": "0x...",
      "argsData": "0x...",
      "bytecodeHash": "0x...", // Hash of deployed bytecode (metadata stripped)
      "blockNumber": 12345
    },
    "pendingImplementation": {
      // Optional: deployed but not yet upgraded
      "address": "0x...",
      "deployment": {
        // Same structure as implementationDeployment
        "txHash": "0x...",
        "argsData": "0x...",
        "bytecodeHash": "0x...",
        "blockNumber": 12346
      }
    }
  }
}
```

### Rocketh Deployment Record

```typescript
{
  address: "0x...",
  abi: [...],
  bytecode: "0x...",           // Creation bytecode
  deployedBytecode: "0x...",   // Runtime bytecode (for change detection)
  argsData: "0x...",           // Encoded constructor args
  metadata: "...",
  transaction?: { hash: "0x..." },
  receipt?: { blockNumber: 12345 }
}
```

### Rocketh Record Names

For a proxied contract `ContractName`:

- `ContractName` - The proxy contract
- `ContractName_Proxy` - Alias for proxy (some patterns use this)
- `ContractName_Implementation` - The implementation contract
- `ContractName_ProxyAdmin` - The proxy admin

## Sync Direction Rules

### Address Book → Rocketh

**When**: Sync step runs, address book has data rocketh doesn't have.

**What syncs**:

- Proxy address → `ContractName` and `ContractName_Proxy`
- Proxy admin address → `ContractName_ProxyAdmin`
- Implementation address → `ContractName_Implementation`

**Implementation address selection**:

1. If `pendingImplementation.address` exists → use pending address
2. Else → use `implementation` address

**Bytecode hash gating**:

- **Only sync implementation if `bytecodeHash` matches local artifact**
- No stored hash → don't sync (can't verify consistency)
- Hash mismatch → don't sync, add "impl outdated" note

**Rationale**: Syncing stale bytecode to rocketh would make rocketh think the deployed code matches local, preventing necessary redeployment.

### Rocketh → Address Book (Backfill)

**When**: Rocketh has deployment metadata that address book lacks.

**What backfills**:

- `txHash`, `argsData`, `bytecodeHash`, `blockNumber`

**Determining "newer"** (blockNumber comparison):

1. Address book has no metadata → rocketh is newer
2. Rocketh has blockNumber, address book doesn't → rocketh is newer
3. Rocketh blockNumber > address book blockNumber → rocketh is newer

**Where to write**:

- For current implementation → `implementationDeployment`
- For pending implementation → `pendingImplementation.deployment`

## Implementation Lifecycle

### State Transitions

```
┌─────────────────────────────────────────┐
│         Initial Deployment              │
│   (deploy creates implementation)       │
└──────────────────┬──────────────────────┘
                   │ deploy script
                   ▼
┌─────────────────────────────────────────┐
│        implementation: 0xIMPL           │
│   implementationDeployment: {...}       │
└──────────────────┬──────────────────────┘
                   │ code changes, deploy new impl
                   ▼
┌─────────────────────────────────────────┐
│        implementation: 0xIMPL           │  (unchanged until upgrade)
│   implementationDeployment: {...}       │
│   pendingImplementation: {              │  (new impl awaiting governance)
│     address: 0xNEW,                     │
│     deployment: {...}                   │
│   }                                     │
└──────────────────┬──────────────────────┘
                   │ governance upgrade TX executed
                   ▼
┌─────────────────────────────────────────┐
│        implementation: 0xNEW            │  (promoted from pending)
│   implementationDeployment: {...}       │  (metadata from pending)
│   (pendingImplementation cleared)       │
└─────────────────────────────────────────┘
```

### Sync Sequence (Logical Order)

When sync runs, execute in this order:

#### Step 1: Reconcile on-chain address

```
IF on-chain impl != address book impl:
  → Update address book impl to match on-chain
  → Wipe stale implementationDeployment (address changed, metadata invalid)
  → Note: This handles external upgrades (from other deployment systems)
```

#### Step 2: Promote pending if upgraded

```
IF pendingImplementation.address == implementation (on-chain):
  → Move pendingImplementation.deployment → implementationDeployment
  → Clear pendingImplementation
  → Add "upgraded" sync note
```

#### Step 3: Sync rocketh ↔ address book

After steps 1-2, address book has correct addresses. Now sync:

- Pick implementation to sync (pending if exists, else current)
- If bytecodeHash matches local → sync to rocketh
- If rocketh has newer metadata → backfill to address book

This sequence ensures:

- Address book always reflects on-chain reality first
- Pending metadata is preserved when promoted
- Rocketh sync naturally goes to the correct location

## Implementation Sync Decision Tree

```
                         ┌─────────────────┐
                         │ Has implAddress?│
                         └────────┬────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │ No                        │ Yes
                    ▼                           ▼
              ┌──────────┐            ┌─────────────────┐
              │ Skip     │            │ Get storedHash  │
              │ (no impl)│            │ from deployment │
              └──────────┘            └────────┬────────┘
                                               │
                                  ┌────────────┴────────────┐
                                  │ storedHash exists?      │
                                  └────────────┬────────────┘
                                               │
                          ┌────────────────────┴────────────────────┐
                          │ No                                      │ Yes
                          ▼                                         ▼
                    ┌──────────────┐                    ┌─────────────────────┐
                    │ Don't sync   │                    │ Compare to local    │
                    │ (unverified) │                    │ artifact hash       │
                    └──────────────┘                    └──────────┬──────────┘
                                                                   │
                                              ┌────────────────────┴────────────────────┐
                                              │ Match?                                  │
                                              └────────────────────┬────────────────────┘
                                                                   │
                                    ┌──────────────────────────────┴──────────────────────────────┐
                                    │ Yes                                                         │ No
                                    ▼                                                             ▼
                          ┌────────────────────┐                                    ┌─────────────────────┐
                          │ Sync to rocketh    │                                    │ Don't sync          │
                          │ + backfill if newer│                                    │ Add "impl outdated" │
                          └────────────────────┘                                    └─────────────────────┘
```

## Backfill Decision (Rocketh → Address Book)

Only runs after successful sync (hash matched). Determines which direction has newer data:

```
                    ┌────────────────────────────────┐
                    │ Rocketh has argsData != '0x'?  │
                    └───────────────┬────────────────┘
                                    │
                      ┌─────────────┴─────────────┐
                      │ No                        │ Yes
                      ▼                           ▼
                ┌──────────┐          ┌───────────────────────────┐
                │ No       │          │ Address book has metadata?│
                │ backfill │          └─────────────┬─────────────┘
                └──────────┘                        │
                                   ┌────────────────┴────────────────┐
                                   │ No                              │ Yes
                                   ▼                                 ▼
                          ┌─────────────────┐        ┌─────────────────────────────┐
                          │ Backfill        │        │ Compare blockNumbers        │
                          │ (book is empty) │        └──────────────┬──────────────┘
                          └─────────────────┘                       │
                                                  ┌─────────────────┴─────────────────┐
                                                  │ rocketh.blockNumber >             │
                                                  │ book.blockNumber?                 │
                                                  └─────────────────┬─────────────────┘
                                                                    │
                                             ┌──────────────────────┴──────────────────────┐
                                             │ Yes                                         │ No
                                             ▼                                             ▼
                                    ┌─────────────────┐                          ┌──────────────────┐
                                    │ Backfill        │                          │ No backfill      │
                                    │ (rocketh newer) │                          │ (book is newer)  │
                                    └─────────────────┘                          └──────────────────┘
```

## Summary

| Scenario                    | Action                                    |
| --------------------------- | ----------------------------------------- |
| No impl address             | Skip                                      |
| Impl exists, no stored hash | Don't sync (unverified)                   |
| Impl exists, hash mismatch  | Don't sync, note "impl outdated"          |
| Impl exists, hash matches   | Sync to rocketh                           |
| After sync, rocketh newer   | Backfill to address book                  |
| Pending upgraded on-chain   | Promote pending to current, clear pending |

## Key Invariants

1. **Bytecode hash is required for sync** - Without it, we can't verify the implementation matches local artifacts
2. **Pending takes precedence** - If pending exists with matching hash, sync pending (not current)
3. **On-chain is authoritative for addresses** - Sync reads actual implementation from chain
4. **BlockNumber determines recency** - Higher block number = newer deployment
5. **Backfill goes to correct location** - Current impl → `implementationDeployment`, pending → `pendingImplementation.deployment`

## Future Enhancements

### Upgrade Timing Tracking

Currently, deployment metadata tracks when the implementation was _deployed_ (`blockNumber`, `timestamp`), but not when the proxy was _upgraded_ to use it. These are separate events:

1. **Deploy** - New implementation contract created (currently tracked)
2. **Upgrade** - Proxy switched to use the new implementation (not tracked)

A future enhancement could add `upgradedAt: { blockNumber, timestamp }` to `implementationDeployment` to capture when the proxy actually started using the implementation. This would require either:

- Querying the chain for the upgrade transaction when promoting pending
- Recording detection time (less accurate but simpler)

This information would be useful for audit trails and understanding the timeline between deployment and activation.
