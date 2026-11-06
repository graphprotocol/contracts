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

Graph Horizon's Ignition modules are deployed together with the Subgraph Service, because the L2Curation and L2GNS artifacts they need come from `@graphprotocol/subgraph-service`. `deploy:protocol` runs from the subgraph-service package only:

```bash
cd ../subgraph-service
npx hardhat deploy:protocol --network hardhat --subgraph-service-config localNetwork
```

See the [Subgraph Service README](../subgraph-service/README.md) for details.

## Testing

- **unit**: Unit tests can be run with `pnpm test`
