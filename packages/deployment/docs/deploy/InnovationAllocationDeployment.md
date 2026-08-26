# InnovationAllocation Deployment

This document describes how `InnovationAllocation` is deployed by this package. For the shared contract's architecture and behaviour, see [DirectAllocation.sol](../../../issuance/contracts/allocate/DirectAllocation.sol) — `InnovationAllocation` is a proxy onto that implementation, not a new contract.

For the goal-level GIP-0089 workflow that reallocates issuance to this target, see [Gip0089.md](../Gip0089.md).

## Component overview

`InnovationAllocation` is a deployable proxy in the `issuance` address book:

- Pattern: OpenZeppelin v5 `TransparentUpgradeableProxy` with a per-proxy `ProxyAdmin` created in the constructor.
- Implementation: `DirectAllocation_Implementation` — **shared** with `DefaultAllocation` and `ReclaimedRewards`. `InnovationAllocation` deploys no new bytecode; see the [shared-implementation drift risk](../Gip0089.md#shared-implementation-drift-risk) in the reference guide.
- Access control: `BaseUpgradeable` (`GOVERNOR_ROLE`, `PAUSE_ROLE`, `OPERATOR_ROLE`).
- Component tag: `InnovationAllocation`. Lifecycle actions: `deploy`, `upgrade`, `configure`, `transfer`.
- Purpose: an allocator-minted `IssuanceAllocator` target. `IssuanceAllocator` mints tokens directly into this contract; it does not distribute them further on its own.

## Lifecycle scripts

| Script                                                                                  | Tag                              | Actor      | Purpose                                                                                                                               |
| --------------------------------------------------------------------------------------- | -------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| [01_deploy.ts](../../deploy/allocate/innovation/01_deploy.ts)                           | `InnovationAllocation,deploy`    | Deployer   | Deploy the proxy onto the shared `DirectAllocation_Implementation`, initialize with deployer as governor                              |
| [02_upgrade.ts](../../deploy/allocate/innovation/02_upgrade.ts)                         | `InnovationAllocation,upgrade`   | Governance | Build a governance TX batch upgrading the proxy to its `pendingImplementation` — only used if the shared implementation changes later |
| [04_configure.ts](../../deploy/allocate/innovation/04_configure.ts)                     | `InnovationAllocation,configure` | Deployer   | Grant `GOVERNOR_ROLE` (governor), `PAUSE_ROLE` (pause guardian), `OPERATOR_ROLE` (`InnovationOperator`)                               |
| [05_transfer_governance.ts](../../deploy/allocate/innovation/05_transfer_governance.ts) | `InnovationAllocation,transfer`  | Deployer   | Revoke deployer `GOVERNOR_ROLE`, transfer per-proxy ProxyAdmin to governor                                                            |
| [09_end.ts](../../deploy/allocate/innovation/09_end.ts)                                 | `InnovationAllocation,all`       | -          | Aggregate end state — verifies deployment, roles, and governance transfer                                                             |
| [10_status.ts](../../deploy/allocate/innovation/10_status.ts)                           | `InnovationAllocation`           | -          | Read-only status display                                                                                                              |

`03_*`, `06_*`, and `07_08_*` slots are intentionally empty (per [ImplementationPrinciples.md](ImplementationPrinciples.md)).

## Role model

`InnovationAllocation` holds the three `BaseUpgradeable` roles, assigned to three distinct actors:

| Role            | Holder                                                                                                                                                            | Can do                                                                                                           |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `GOVERNOR_ROLE` | Protocol governor                                                                                                                                                 | Everything except `sendTokens` — e.g. `setIssuanceAllocator`, role administration, proxy upgrades via ProxyAdmin |
| `PAUSE_ROLE`    | Pause guardian                                                                                                                                                    | `pause()` / `unpause()`                                                                                          |
| `OPERATOR_ROLE` | `InnovationOperator` — The Graph Foundation multisig (mainnet `0x7700d56D2cFAFa620048633B2586b063eCD93dd1`, Sepolia `0xc306C6D55f3E0F3C6758CCc0E8c448c90A4c79fe`) | `sendTokens(to, amount)` only                                                                                    |

`InnovationOperator` holds **only** `OPERATOR_ROLE`. It never holds `GOVERNOR_ROLE` and is never the ProxyAdmin owner — those go to the protocol governor.

What actually enforces that split, check by check:

| Property                                                            | Checked by                                                                                                                                                                                                                                                                                                                                            |
| ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Exactly one `OPERATOR_ROLE` holder, and it is `InnovationOperator`  | `checkOperatorRole` ([lib/contract-checks.ts](../../lib/contract-checks.ts)) — a thin wrapper over `checkExclusiveRoleHolder`; it reads `OPERATOR_ROLE` only                                                                                                                                                                                          |
| Exactly one `GOVERNOR_ROLE` holder, and it is the protocol governor | `checkExclusiveRoleHolder` ([lib/contract-checks.ts](../../lib/contract-checks.ts)), rendered by the component status                                                                                                                                                                                                                                 |
| Governor holds `GOVERNOR_ROLE`, pause guardian holds `PAUSE_ROLE`   | `checkInnovationAllocationConfigured` ([lib/preconditions.ts](../../lib/preconditions.ts))                                                                                                                                                                                                                                                            |
| Deployer no longer holds `GOVERNOR_ROLE`                            | `checkDeployerRevoked` ([lib/preconditions.ts](../../lib/preconditions.ts)) in the transfer step and the `--tags GIP-0089,all` end gate — both write-capable runs with a real deployer key. On the read-only component status this is covered by the `GOVERNOR_ROLE` exclusivity row instead: a deployer that still holds the role is a second holder |
| ProxyAdmin owned by the protocol governor                           | `checkProxyAdminTransferred` ([lib/preconditions.ts](../../lib/preconditions.ts)), and the ProxyAdmin line in the component status                                                                                                                                                                                                                    |

The read-only status deliberately does **not** compare against the deployer address: `hardhat.config.ts` supplies a dummy key for any `deploy` run whose `--tags` carry no action verb, so `eth_accounts[0]` on such a run is an address that can never hold a role, and a row built on it would pass without evaluating anything. Exclusivity is the assertion that holds with no deployer account.

`checkExclusiveRoleHolder` reads one role at a time and does not look at the ProxyAdmin — the rows above are what cover the rest. An extra `OPERATOR_ROLE` holder could call `sendTokens` and drain the contract, which is why the count assertion is exact.

## Withdrawals

`InnovationAllocation` is a passive receiver — `IssuanceAllocator` mints tokens into it on each distribution; there is no push mechanism out. Withdrawal is the single function `ISendTokens.sendTokens(address to, uint256 amount)`:

```solidity
function sendTokens(address to, uint256 amount) external override onlyRole(OPERATOR_ROLE) whenNotPaused {
  require(GRAPH_TOKEN.transfer(to, amount), SendTokensFailed(to, amount));
  emit TokensSent(to, amount);
}
```

- Callable only by `OPERATOR_ROLE` — the `InnovationOperator` multisig.
- Blocked entirely while the contract is paused (`whenNotPaused`) — the pause guardian can halt all withdrawals independent of the operator.
- No allocation or vesting logic — the operator can send any amount up to the contract's GRT balance to any address, at any cadence. Spending policy is off-chain, enforced by the multisig's own signing process, not by this contract.

## What does NOT happen here

The reallocation of issuance to this target is a GIP-0089 activation step, not a component lifecycle action. It lives in [../../deploy/gip/0089/](../../deploy/gip/0089/) and is a governance TX:

- `IA.setTargetAllocation(RewardsManager, 0, 96.584)` — reduces RM's self-mint rate first
- `IA.setTargetAllocation(InnovationAllocation, 24.146, 0)` — routes the freed 20% to this target, allocator-minted

See [Gip0089.md](../Gip0089.md) for the full picture, including why the ordering above is load-bearing.

No keeper ships in this package. `IssuanceAllocator.distributeIssuance()` is permissionless — anyone can call it, and every `setTargetAllocation` call also triggers a distribution — so no scheduled job is required to keep `InnovationAllocation`'s balance current.

## Single-component usage

```bash
# Read-only status
pnpm hardhat deploy --tags InnovationAllocation --network <network>

# Lifecycle steps
pnpm hardhat deploy --tags InnovationAllocation,deploy    --network <network>
pnpm hardhat deploy --tags InnovationAllocation,configure --network <network>
pnpm hardhat deploy --tags InnovationAllocation,transfer  --network <network>
pnpm hardhat deploy --tags InnovationAllocation,upgrade   --network <network>
```

## Verification checklist

Run `--tags InnovationAllocation` (component status) or `--tags GIP-0089` (goal status) to inspect on-chain state. Both are read-only.

The component status covers every item below: implementation address, the `GOVERNOR_ROLE` / `PAUSE_ROLE` / `OPERATOR_ROLE` grant rows, `OPERATOR_ROLE` and `GOVERNOR_ROLE` exclusivity, the ProxyAdmin owner line, and `paused()`. This list is for reviewing a finished deployment by hand.

Note that `--tags GIP-0089,all` is **not** a read-only verification — `all` is an action verb and the run can deploy the proxy, redeploy the shared implementation on artifact drift, and stage governance batches. Use it only post-deployment, as the [runbook G5](../Gip0089Runbook.md#gate-g5) prescribes.

### Bytecode

- Proxy implementation matches `DirectAllocation_Implementation` — the same address as `DefaultAllocation` and `ReclaimedRewards`

### Access control

- Protocol governor holds `GOVERNOR_ROLE` — and is the **only** holder
- Pause guardian holds `PAUSE_ROLE`
- `InnovationOperator` holds `OPERATOR_ROLE` — and is the **only** holder
- Deployer does **not** hold `GOVERNOR_ROLE` — implied by the governor being the sole holder above, and asserted directly by `checkDeployerRevoked` in the transfer step
- Per-proxy `ProxyAdmin` is owned by the protocol governor

### Configuration

- `paused()` is `false`

### Activation (GIP-0089)

- `IssuanceAllocator.getTargetAllocation(InnovationAllocation)` shows `allocatorMintingRate == 24.146` (mainnet) / `1.2073` (testnet), `selfMintingRate == 0`
- `RewardsManager`'s raw `issuancePerBlock` is unchanged (120.73 mainnet / 6.0365 testnet)
