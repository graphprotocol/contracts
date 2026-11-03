# 🌅 Graph Horizon 🌅

Graph Horizon is the next evolution of the Graph Protocol.

## Configuration

The following environment variables might be required:

| Variable               | Description                                                                     |
| ---------------------- | ------------------------------------------------------------------------------- |
| `ARBISCAN_API_KEY`     | Arbiscan API key - for contract verification                                    |
| `ARBITRUM_ONE_RPC`     | Arbitrum One RPC URL - defaults to `https://arb1.arbitrum.io/rpc`               |
| `ARBITRUM_SEPOLIA_RPC` | Arbitrum Sepolia RPC URL - defaults to `https://sepolia-rollup.arbitrum.io/rpc` |
| `LOCALHOST_RPC`        | Localhost RPC URL - defaults to `http://localhost:8545`                         |

You can set them using Hardhat:

```bash
npx hardhat vars set <variable>
```

## Build

```bash
pnpm install
pnpm build
```

## Deployment

Note that this instructions will help you deploy Graph Horizon contracts, but no data service will be deployed. If you want to deploy the Subgraph Service please refer to the [Subgraph Service README](../subgraph-service/README.md) for deploy instructions.

### New deployment

To deploy Graph Horizon from scratch run the following command:

```bash
npx hardhat deploy:protocol --network hardhat
```

## Testing

- **unit**: Unit tests can be run with `pnpm test`
