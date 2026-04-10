# Local Fork Testing

Fork testing allows simulating deployments against real network state without spending gas or requiring governance permissions.

## Ephemeral Fork (single session)

State is lost when the command exits. Good for quick testing.

```bash
# Run full deployment flow against forked arbitrumSepolia
FORK_NETWORK=arbitrumSepolia npx hardhat deploy --tags sync,RewardsManager:deploy --network fork
```

## Persistent Fork (multiple sessions)

State persists between commands. Good for iterative testing.

```bash
# Terminal 1 - start persistent forked node using anvil (Foundry)
# Use --chain-id 31337 so hardhat's localhost network can connect
anvil --fork-url https://sepolia-rollup.arbitrum.io/rpc --chain-id 31337
```

```bash
# Terminal 2 - run deploys against it
npx hardhat deploy:reset-fork --network localhost
npx hardhat deploy:status --network localhost
npx hardhat deploy --network localhost --skip-prompts --tags sync
npx hardhat deploy --network localhost --skip-prompts --tags RewardsManager
npx hardhat deploy:execute-governance --network localhost
```

Or for Arbitrum One:

```bash
anvil --fork-url https://arb1.arbitrum.io/rpc --chain-id 31337
```

**Important**:

- Terminal 1: Use anvil (from Foundry) instead of `hardhat node` - Hardhat v3's node command doesn't properly support the `--fork` flag
- Terminal 1: Use `--chain-id 31337` - anvil defaults to the forked chain's ID (421614) but hardhat's localhost expects 31337

### Fork Network Detection

The fork network (which chain is being forked) is **auto-detected** from anvil's RPC metadata. When you run against localhost, deploy scripts query `anvil_nodeInfo` to get the fork URL and match it against known network RPC hostnames.

You can also set `FORK_NETWORK` explicitly to override auto-detection:

```bash
export FORK_NETWORK=arbitrumSepolia
```

**Safe on real networks**: `FORK_NETWORK` is automatically ignored when running against real networks (`--network arbitrumSepolia`, `--network arbitrumOne`). Fork mode only activates on local networks (localhost, fork, hardhat), so you don't need to unset `FORK_NETWORK` when switching between fork testing and real deployments.

## Architecture

```
fork/                         # Fork state (outside deployments/ to avoid rocketh conflicts)
└── <environment>/            # Rocketh environment (fork, localhost)
    └── <FORK_NETWORK>/       # Fork source network
        ├── horizon-addresses.json
        ├── subgraph-service-addresses.json
        ├── issuance-addresses.json
        └── txs/
            └── upgrade-*.json

deployments/                  # Managed by rocketh (deployment records, .chain files)
└── <environment>/
    └── ...
```

**Fork state organization:**

- Fork state is stored under `fork/<environment>/<FORK_NETWORK>/`
  - Separate from `deployments/` so rocketh manages its own directory cleanly
  - `<environment>` is the rocketh environment (fork, localhost)
  - `<FORK_NETWORK>` is the source network being forked (arbitrumSepolia, arbitrumOne)
- This prevents addresses from wrong network being used if fork target changes
- Address books and governance TXs are stored together
- State persists across fork sessions (rocketh's data is ephemeral, this is not)

## Key Points

| Setting               | Value                              | Purpose                                                        |
| --------------------- | ---------------------------------- | -------------------------------------------------------------- |
| `FORK_NETWORK`        | `arbitrumSepolia` or `arbitrumOne` | Override auto-detected fork network (ignored on real networks) |
| `SHOW_ADDRESSES`      | `0`, `1` (default), or `2`         | Address display: none/short/full                               |
| `--network fork`      | in-process EDR                     | Ephemeral, fast startup                                        |
| `--network localhost` | external node                      | Persistent state                                               |

## Configuration

### Address Display

Control how addresses are shown in sync output with `SHOW_ADDRESSES`:

```bash
# Show full addresses (default)
SHOW_ADDRESSES=2 npx hardhat deploy --tags sync --network fork

# Show truncated addresses (0x1234567890...)
SHOW_ADDRESSES=1 npx hardhat deploy --tags sync --network fork

# Hide addresses completely
SHOW_ADDRESSES=0 npx hardhat deploy --tags sync --network fork
```

**Output examples:**

```
# SHOW_ADDRESSES=2 (default - full addresses)
✓   SubgraphService @ 0xc24A3dAC5d06d771f657A48B20cE1a671B78f26b → 0xEc11f71070503D29098149195f95FEb1B1CeF93E

# SHOW_ADDRESSES=1 (truncated)
✓   SubgraphService @ 0xc24A3dAC... → 0xEc11f710...

# SHOW_ADDRESSES=0 (hidden)
✓   SubgraphService
```

## Reset Fork State

```bash
# Use the reset task (deletes entire network directory)
npx hardhat deploy:reset-fork --network localhost
# Or for ephemeral fork:
npx hardhat deploy:reset-fork --network fork
```

## Limitations

- **On-chain state**: Only persists with persistent node (anvil)
- **rocketh deployment files**: Don't persist for forks (by design)
- **Contract size**: Fork allows unlimited contract size (Arbitrum supports >24KB)

## Prerequisites

- **Foundry**: Install via `curl -L https://foundry.paradigm.xyz | bash && foundryup`

## Local Network (rem-local-network)

The `localNetwork` network targets the Graph local network docker-compose stack (chain ID 1337).
Unlike fork mode, contracts are deployed fresh from scratch.

```bash
# Deploy a single contract via its component lifecycle
npx hardhat deploy --tags IssuanceAllocator,deploy --network localNetwork

# Or run the full GIP-0088 upgrade phase
npx hardhat deploy --tags GIP-0088:upgrade,deploy --network localNetwork
```

**Key differences from fork mode:**

- Chain ID 1337 (not 31337)
- No `FORK_NETWORK` env var needed
- Address books use `addresses-local-network.json` files (symlinked to mounted config)
- Deployer is also governor (direct execution, no governance batch files)
- Uses standard test mnemonic (`test test test ... junk`)

**Environment:**

- RPC: `http://chain:8545` (override with `LOCAL_NETWORK_RPC`)
- Address books are populated by Phase 1 (hardhat-graph-protocol deploys Horizon + SubgraphService)
- Phase 2+ deployment scripts use this package to deploy additional contracts (e.g., issuance)

## See Also

- [GovernanceWorkflow.md](./GovernanceWorkflow.md) - Production deployment flow
