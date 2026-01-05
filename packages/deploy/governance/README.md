# Issuance Governance Helpers

This folder contains governance-focused tooling for the Issuance contracts.

## Rewards Eligibility Upgrade Safe batch

The Hardhat task below generates a Gnosis Safe Transaction Builder JSON batch that:

1. Upgrades the on-chain `RewardsManager` proxy to a new implementation (V6).
2. Accepts the proxy upgrade.
3. Sets the `IssuanceAllocator` on `RewardsManager`.
4. Sets the `RewardsEligibilityOracle` on `RewardsManager`.

All four steps are emitted as _governance-only_ transactions – nothing is executed locally.

### Usage

From the packages/deploy directory:

```bash
npx hardhat issuance:build-rewards-eligibility-upgrade \
  --network arbitrumSepolia \
  --rewards-manager-implementation 0xYourNewImplementation
```

The script will:

- Read `GraphProxyAdmin` and `RewardsManager` from the Horizon address book for the given chain ID.
- Read `IssuanceAllocator` and `RewardsEligibilityOracle` from `@graphprotocol/issuance/addresses.json`.
- Emit a Safe Tx Builder JSON file in the current directory (or in `--outputDir` if provided).

You can then upload that JSON file into the Safe Transaction Builder UI for review and execution by governance.

## Issuance Contract Upgrade Safe batch

The Hardhat task below generates a Gnosis Safe Transaction Builder JSON batch to upgrade an issuance contract (`IssuanceAllocator`, `RewardsEligibilityOracle`, or `PilotAllocation`) via the `GraphIssuanceProxyAdmin`.

This is used when upgrading the implementation of these contracts to fix bugs or add features.

### Usage

From the packages/deploy directory:

```bash
npx hardhat issuance:build-contract-upgrade \
  --network arbitrumSepolia \
  --contract-name IssuanceAllocator \
  --new-implementation 0xYourNewImplementation
```

Optional parameters:

- `--call-data` - Optional calldata for `upgradeAndCall` (defaults to `0x`)
- `--graph-issuance-proxy-admin` - ProxyAdmin address (defaults to address book value)
- `--output-dir` - Output directory for the Safe TX JSON file
- `--tx-builder-template` - Path to custom Safe TX Builder template

The script will:

- Read `GraphIssuanceProxyAdmin` and the target contract address from `@graphprotocol/issuance/addresses.json`.
- Generate a call to `GraphIssuanceProxyAdmin.upgradeAndCall()` with the new implementation.
- Emit a Safe Tx Builder JSON file in the current directory (or in `--outputDir` if provided).

You can then upload that JSON file into the Safe Transaction Builder UI for review and execution by governance.
