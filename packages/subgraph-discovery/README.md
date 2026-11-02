# Subgraph Discovery

The Graph subgraph discovery and curation contracts: `L2GNS`, `L2Curation`, `GNS`, `SubgraphNFT`, `SubgraphNFTDescriptor`, `GraphCurationToken`, their storage contracts, `Multicall` and the `Base58Encoder` and `HexStrings` libraries.

`L2GNS` and `L2Curation` are the contracts deployed on Arbitrum. `GNS` is the abstract base of `L2GNS`; it is not what runs on Ethereum mainnet, where the L1 GNS implementation is held in `packages/legacy`.

The contracts compile with solc 0.7.6 (optimizer enabled, 200 runs).

## Usage

```solidity
import { L2GNS } from '@graphprotocol/subgraph-discovery/contracts/l2/discovery/L2GNS.sol';
```

Hardhat artifacts are published under `@graphprotocol/subgraph-discovery/artifacts/` and typechain types under `@graphprotocol/subgraph-discovery/types`.

## Development

```bash
pnpm build       # compile with Hardhat
pnpm test:self   # Foundry tests
```
