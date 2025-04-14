# hardhat-graph-protocol

A Hardhat plugin for integrating with The Graph Protocol, providing easy access to deployment addresses and configuration for Graph Protocol contracts.

### Features

- **Protocol deployments** - Provides a simple interface to interact with protocol contracts without having to configure contract addresses or ABIs.
- **Transaction logging** - Transactions made via the plugin are automatically awaited and logged.
- **Accounts** - Provides account management methods for convenience, following protocol conventions for account derivation
- **Secure accounts** - Integrates seamlessly with [hardhat-secure-accounts](https://www.npmjs.com/package/hardhat-secure-accounts)

## Installation

```bash
# Install as a dev dependency
pnpm add --dev hardhat-graph-protocol
```

## Configuration

Add the plugin to your `hardhat.config.ts`:

```ts
import "hardhat-graph-protocol";
```

### Using @graphprotocol/toolshed
To use the plugin you'll need to configure the target networks. We recommend using our base hardhat configuration which can be imported from `@graphprotocol/toolshed`:

```ts
import { hardhatBaseConfig, networksUserConfig } from '@graphprotocol/toolshed/hardhat'
import "hardhat-graph-protocol";

const config: HardhatUserConfig = {
  ...networksUserConfig,
  // rest of config
}

export default config // or just "export default hardhatBaseConfig"
```

### Manual configuration
To manually configure target networks:

**Hardhat: Network config**
```ts
  networks: {
    arbitrumOne: { 
      chainId: 42161,
      url: `https://arbitrum-one.infura.io/v3/123456`
      deployments: {
        horizon: '/path/to/horizon/addresses.json,
        subgraphService: 'path/to/subgraph-service/addresses.json'
      }
    },
  }
```
**Hardhat: Graph config**

Additionally, the plugin adds a new config field to hardhat's config file: `graph`. This can be used used to define defaults for all networks:

```ts
  ...
  networks: {
    ...
  },
  graph: {
    deployments: {
      horizon: '/path/to/horizon/addresses.json,
      subgraphService: 'path/to/subgraph-service/addresses.json'
    },
  },
  ...
```

## Usage

This plugin exposes functionality via a simple API:

```ts
const graph = hre.graph()
```

The interface for the graph object can be found [here](src/types.ts), it's expanded version lookg like this:

```ts
export type GraphRuntimeEnvironment = {
  [deploymentName]: {
    contracts: DeploymentContractsType,
    addressBook: DeploymentAddressBookType,
    actions: DeplyomentActionsType
  },
  provider: HardhatEthersProvider
  chainId: number
  accounts: {
    getAccounts: () => Promise<GraphAccounts>
    getDeployer: (accountIndex?: number) => Promise<HardhatEthersSigner>
    getGovernor: (accountIndex?: number) => Promise<HardhatEthersSigner>
    getArbitrator: (accountIndex?: number) => Promise<HardhatEthersSigner>
    getPauseGuardian: (accountIndex?: number) => Promise<HardhatEthersSigner>
    getSubgraphAvailabilityOracle: (accountIndex?: number) => Promise<HardhatEthersSigner>
    getGateway: (accountIndex?: number) => Promise<HardhatEthersSigner>
    getTestAccounts: () => Promise<HardhatEthersSigner[]>
  }
}
```

### Deployments

The plugin provides one object for each configured deployment, this object allows easily interacting with the associated deployment with a few additional features. The current deployments that are supported: `horizon` and `subgraphService`.

Each deployment will be of the form:
```ts
  [deploymentName]: {
    contracts: DeploymentContractsType,
    addressBook: DeploymentAddressBookType,
    actions: DeplyomentActionsType
  },
```
Where:
- `contracts`: an object with all the contracts available in the deployment, already instanced, fully typed and ready to go.
- `addressBook`: an object allowing read and write access to the deployment's address book.
- `actions`: (optional) an object with helper functions to perform common actions in the associated deployment.

**Transaction logging**

Any transactions made using the `contracts` object will be automatically logged both to the console and to a file:
- `file`, in the project's root directory: `tx-YYYY-MM-DD.log`
- `console`, not shown by default. Run with `DEBUG=toolshed:tx` to enable them.

Note that this does not apply to getter functions (`view` or `pure`) as those are not state modifying calls.
An example log output:
```
[2025-04-10T20:32:37.182Z] > Sending transaction: HorizonStaking.addToProvision
[2025-04-10T20:32:37.182Z]    = Sender: 0xACa94ef8bD5ffEE41947b4585a84BdA5a3d3DA6E
[2025-04-10T20:32:37.182Z]    = Contract: 0x865365C425f3A593Ffe698D9c4E6707D14d51e08
[2025-04-10T20:32:37.182Z]    = Params: [ 0xACa94ef8bD5ffEE41947b4585a84BdA5a3d3DA6E, 0x1afb3ce06A1b3Cfb065DA4821c6Fa33b8CfC3485, 100000000000000000000 ]
[2025-04-10T20:32:37.182Z]    = TxHash: 0x0e76c384a80f9f0402eb74de40c0456ef808d7afb4de68d451f5ed95b4be5c8a
[2025-04-10T20:32:37.183Z]    ✔ Transaction succeeded!
[2025-04-10T20:32:40.936Z] > Sending transaction: HorizonStaking.thaw
[2025-04-10T20:32:40.936Z]    = Sender: 0xACa94ef8bD5ffEE41947b4585a84BdA5a3d3DA6E
[2025-04-10T20:32:40.936Z]    = Contract: 0x865365C425f3A593Ffe698D9c4E6707D14d51e08
[2025-04-10T20:32:40.936Z]    = Params: [ 0xACa94ef8bD5ffEE41947b4585a84BdA5a3d3DA6E, 0x1afb3ce06A1b3Cfb065DA4821c6Fa33b8CfC3485, 100000000000000000000 ]
[2025-04-10T20:32:40.936Z]    = TxHash: 0x5422a1e975688952e13a455498c4f652a090d619bec414662775fc9d8cbd0af6
[2025-04-10T20:32:40.946Z]    ✔ Transaction succeeded!
```

**Transaction auto-awaiting**

Any transactions made using the `contracts` object will be automatically awaited:

```ts
const graph = hre.graph()

// The transaction is automatically awaited, no need to await tx.wait() it
const tx = await graph.horizon.contracts.GraphToken.approve('0xDEADBEEF', 100)

// But you can still do it if you need more confirmations for example
await tx.wait(10)
```

**Examples**
```js
const graph = hre.graph()
const { GraphPayments, HorizonStaking, GraphToken } = graph.horizon.contracts
const { provision } = graph.horizon.actions

// Print GraphPayment's protocol cut
await GraphPayments.PROTOCOL_PAYMENT_CUT()
10000n

// Provision some GRT to a data service
await GraphToken.connect(signer).approve(HorizonStaking.target, 100_000_000)
await HorizonStaking.connect(signer).stake(100_000_000)
await HorizonStaking.connect(signer).provision(signer.address, dataService.address, 100_000_000, 10_000, 42_690)

// Do the same but using actions - in this case the `provision` helper also approves and stakes
await provision(signer, [signer.address, dataService.address, 100_000_000, 10_000, 42_690])

// Read the address book 
const entry = graph.horizon.addressBook.getEntry('HorizonStaking')
console.log(entry.address) // HorizonStaking proxy address
console.log(entry.implementation) // HorizonStaking implementation address
```

### Accounts

The plugin provides helper functions to derive signers from the configured accounts in hardhat config:
```ts
  hardhat: {
    chainId: 31337,
    accounts: {
      mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
    },
  ...
  },
```

| Function | Description | Default account derivation index |
|----------|-------------|-------------|
| `getAccounts()` | Returns all the accounts listed below | - |
| `getDeployer()` | Returns the deployer signer | 0 |
| `getGovernor()` | Returns the governor signer | 1 |
| `getArbitrator()` | Returns the arbitrator signer | 2 |
| `getPauseGuardian()` | Returns the pause guardian signer | 3 |
| `getSubgraphAvailabilityOracle()` | Returns a service provider signer | 4 |
| `getGateway()` | Returns the gateway signer | 5 |
| `getTestAccounts()` | Returns the test signers | 6-20 |

Note that these are just helper functions to enforce a convention on which index to use for each account. These might not match what is configured in the target protocol deployment.

For any of the accounts listed above these are equivalents:

```ts
const graph = hre.graph()

// These two should match
const governor = await graph.accounts.getGovernor() // By default governor uses derivation index 1
const governorFromEthers = (await hre.ethers.getSigners())[1]
```

## Development: TypeScript support

When using the plugin from within this monorepo, TypeScript may fail to properly apply the type extension typings. To work around this issue:

1. Create a file at `types/hardhat-graph-protocol.d.ts`
2. Copy the contents from the `type-extensions.ts` file in this repository into the new file

This will ensure proper TypeScript type support for the plugin.
