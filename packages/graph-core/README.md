# Graph Core

Governance and proxy contracts shared by The Graph Protocol: `Controller`, `Governed`, `Managed`, `Pausable`, and the `GraphProxy` upgrade pattern (`GraphProxy`, `GraphProxyAdmin`, `GraphProxyStorage`, `GraphUpgradeable`).

The contracts compile with solc 0.7.6 (optimizer enabled, 200 runs) to keep their bytecode identical to the deployed protocol.

## Usage

```solidity
import { Managed } from '@graphprotocol/graph-core/contracts/governance/Managed.sol';
```

Hardhat artifacts are published under `@graphprotocol/graph-core/artifacts/` and typechain types under `@graphprotocol/graph-core/types`.

## Development

```bash
pnpm build       # compile with Hardhat
pnpm test:self   # Foundry tests
```
