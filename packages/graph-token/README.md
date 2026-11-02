# Graph Token

The Graph token and the Arbitrum bridge contracts: `GraphToken`, `L2GraphToken`, `GraphTokenUpgradeable`, `TokenUtils`, `L1GraphTokenGateway`, `L2GraphTokenGateway`, `GraphTokenGateway`, `BridgeEscrow` and the Arbitrum messenger helpers.

`GraphToken`, `L1GraphTokenGateway` and `BridgeEscrow` here are not the code running on mainnet. The mainnet sources are held in `packages/legacy`.

The contracts compile with solc 0.7.6 (optimizer enabled, 200 runs).

## Usage

```solidity
import { TokenUtils } from '@graphprotocol/graph-token/contracts/utils/TokenUtils.sol';
```

Hardhat artifacts are published under `@graphprotocol/graph-token/artifacts/` and typechain types under `@graphprotocol/graph-token/types`.

## Development

```bash
pnpm build       # compile with Hardhat
pnpm test:self   # Foundry tests
```
