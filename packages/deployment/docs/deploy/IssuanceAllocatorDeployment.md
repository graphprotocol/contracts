# IssuanceAllocator Deployment

This document describes how `IssuanceAllocator` is deployed by this package. For contract architecture, behaviour, and technical details, see [IssuanceAllocator.md](../../../issuance/contracts/allocate/IssuanceAllocator.md).

For the goal-level GIP-0088 workflow that orchestrates IA together with the rest of the upgrade, see [Gip0088.md](../Gip0088.md).

## Component overview

`IssuanceAllocator` is a deployable proxy in the `issuance` address book:

- Pattern: OpenZeppelin v5 `TransparentUpgradeableProxy` with a per-proxy `ProxyAdmin` created in the constructor.
- Access control: `BaseUpgradeable` (`GOVERNOR_ROLE`, `PAUSE_ROLE`).
- Component tag: `IssuanceAllocator`. Lifecycle actions: `deploy`, `upgrade`, `configure`, `transfer`.
- Default target: a separate `DefaultAllocation` proxy ([../../deploy/allocate/default/](../../deploy/allocate/default/)) that holds any unallocated issuance as a safety net.

## Lifecycle scripts

| Script                                                                                 | Tag                           | Actor      | Purpose                                                                    |
| -------------------------------------------------------------------------------------- | ----------------------------- | ---------- | -------------------------------------------------------------------------- |
| [01_deploy.ts](../../deploy/allocate/allocator/01_deploy.ts)                           | `IssuanceAllocator,deploy`    | Deployer   | Deploy proxy + implementation, initialize with deployer as governor        |
| [02_upgrade.ts](../../deploy/allocate/allocator/02_upgrade.ts)                         | `IssuanceAllocator,upgrade`   | Governance | Build governance TX batch upgrading the proxy to its pendingImplementation |
| [04_configure.ts](../../deploy/allocate/allocator/04_configure.ts)                     | `IssuanceAllocator,configure` | Deployer   | Set issuance rate (matches RM), grant `GOVERNOR_ROLE` and `PAUSE_ROLE`     |
| [06_transfer_governance.ts](../../deploy/allocate/allocator/06_transfer_governance.ts) | `IssuanceAllocator,transfer`  | Deployer   | Revoke deployer `GOVERNOR_ROLE`, transfer per-proxy ProxyAdmin to gov      |
| [09_end.ts](../../deploy/allocate/allocator/09_end.ts)                                 | `IssuanceAllocator,all`       | -          | Aggregate end state — verifies upgrade has been executed                   |
| [10_status.ts](../../deploy/allocate/allocator/10_status.ts)                           | `IssuanceAllocator`           | -          | Read-only status display                                                   |

`03_*`, `05_*`, and `07_08_*` slots are intentionally empty (per [ImplementationPrinciples.md](ImplementationPrinciples.md)).

## What does NOT happen here

The following operations are part of GIP-0088 activation, not the IA component lifecycle. They live in [../../deploy/gip/0088/](../../deploy/gip/0088/) and are governance TXs:

- `IA.setTargetAllocation(RM, 0, rate)` — registers RM as the 100% self-minting target
- `IA.setDefaultTarget(DA)` — wires the safety net
- `RM.setIssuanceAllocator(IA)` — RM starts querying IA for its issuance rate
- `GraphToken.addMinter(IA)` — gives IA minter authority (only needed for allocator-minting targets)
- `IA.setTargetAllocation(RAM, allocatorRate, selfRate)` — distributes issuance to `RecurringAgreementManager`

These are bundled into the `GIP-0088:upgrade,upgrade` and `GIP-0088:issuance-connect` / `GIP-0088:issuance-allocate` governance batches. See [Gip0088.md](../Gip0088.md) for the full picture.

## Single-component usage

```bash
# Read-only status
pnpm hardhat deploy --tags IssuanceAllocator --network <network>

# Lifecycle steps
pnpm hardhat deploy --tags IssuanceAllocator,deploy --network <network>
pnpm hardhat deploy --tags IssuanceAllocator,configure --network <network>
pnpm hardhat deploy --tags IssuanceAllocator,transfer --network <network>
pnpm hardhat deploy --tags IssuanceAllocator,upgrade --network <network>
```

The same scripts run as part of the goal-level GIP-0088 flow when invoked via `--tags GIP-0088:upgrade,<verb>`.

## Verification checklist

Run `--tags IssuanceAllocator` (component status) or `--tags GIP-0088:upgrade` (goal status) to inspect on-chain state. The status output already covers everything below — this list is for reviewing a finished deployment by hand.

### Bytecode

- Implementation bytecode matches the expected `IssuanceAllocator` contract

### Access control

- Protocol governor holds `GOVERNOR_ROLE`
- Pause guardian holds `PAUSE_ROLE`
- Deployer does **not** hold `GOVERNOR_ROLE` (asserted by `checkDeployerRevoked` in the transfer step)
- Per-proxy `ProxyAdmin` is owned by the protocol governor

### Configuration

- `getIssuancePerBlock()` matches `RewardsManager.issuancePerBlock()`
- `paused()` is `false`

### Activation (GIP-0088)

- `RewardsManager.getIssuanceAllocator()` returns the IA address
- `GraphToken.isMinter(IA)` is `true` (only when allocator-minting targets exist)
- `getTargetAllocation(RM)` shows `selfMintingRate == issuancePerBlock`, `allocatorMintingRate == 0`
- `getTargetAllocation(RAM)` matches `config/<network>.json5` rates
- Default target points at `DefaultAllocation`
