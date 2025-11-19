# Issuance Governance Helpers

This folder contains governance-focused tooling for the Issuance contracts.

## Rewards Eligibility Upgrade Safe batch

The Hardhat task below generates a Gnosis Safe Transaction Builder JSON batch that:

1. Upgrades the on-chain `RewardsManager` proxy to a new implementation (V6).
2. Sets the `IssuanceAllocator` on `RewardsManager`.
3. Sets the `RewardsEligibilityOracle` on `RewardsManager`.

All three steps are emitted as _governance-only_ transactions – nothing is executed locally.

### Usage

From the monorepo root:

```bash
cd packages/issuance/deploy

npx hardhat issuance:build-rewards-eligibility-upgrade \
  --network arbitrumSepolia \
  --rewardsManagerImplementation 0xYourNewImplementation
```

The script will:

- Read `GraphProxyAdmin` and `RewardsManager` from the Horizon address book for the given chain ID.
- Read `IssuanceAllocator` and `RewardsEligibilityOracle` from `@graphprotocol/issuance/addresses.json`.
- Emit a Safe Tx Builder JSON file in the current directory (or in `--outputDir` if provided).

You can then upload that JSON file into the Safe Transaction Builder UI for review and execution by governance.
