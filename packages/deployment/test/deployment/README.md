# Deployment test suites

On-chain assertion suites for the GIP-0088 issuance contracts — IssuanceAllocator,
RewardsEligibilityOracle (A and B), RecurringAgreementManager, DefaultAllocation
and ReclaimedRewards. They are the `SUITE` mechanism behind gates `G6`/`G10`/`G12`
of [Gip0088Runbook.md](../../docs/Gip0088Runbook.md).

Unlike the unit tests under `test/`, these run against a **real deployment** —
fork, testnet, or mainnet — so they need a network.

## Running

```bash
# Fork rehearsal (anvil at 127.0.0.1:8545, forking arbitrumSepolia)
FORK_NETWORK=arbitrumSepolia TEST_DEPLOYMENT_NETWORK=localhost pnpm test:deployment

# Testnet
TEST_DEPLOYMENT_NETWORK=arbitrumSepolia pnpm test:deployment
```

| Variable                                    | Purpose                                                                                                                    |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `TEST_DEPLOYMENT_NETWORK`                   | `localhost` \| `arbitrumSepolia` \| `arbitrumOne`. **Unset → every suite skips** (so `pnpm test` never touches a network). |
| `TEST_DEPLOYMENT_RPC`                       | Override the RPC URL for `localhost` (default `http://127.0.0.1:8545`).                                                    |
| `ARBITRUM_SEPOLIA_RPC` / `ARBITRUM_ONE_RPC` | RPC URLs for the testnet / mainnet targets.                                                                                |
| `FORK_NETWORK`                              | When on a fork node, the forked network — selects which address book to read.                                              |
| `TEST_DEPLOYMENT_DEPLOYER`                  | Optional. When set, also asserts the deployer's `GOVERNOR_ROLE` is revoked.                                                |

## What they assert

Each contract's suite checks the deployer-scoped end-state — proxy wiring
(ERC-1967 slots), ProxyAdmin ownership transferred to the governor,
implementation initialization-locked, role grants and configured parameters —
reusing the precondition functions in `lib/preconditions.ts` and
`lib/contract-checks.ts`.

Goal-level **activation** state (IA connected to RM, the active eligibility
oracle, issuance allocated) is intentionally out of scope here — it is asserted
by `pnpm hardhat deploy --tags GIP-0088,all`.
