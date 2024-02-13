# Graph Runtime Environment (GRE)

GRE is a hardhat plugin that extends hardhat's runtime environment to inject additional functionality related to the usage of the Graph Protocol.

### Features

- Provides a simple interface to interact with protocol contracts
- Exposes protocol configuration via graph config file and address book
- Provides account management methods for convenience
- Detailed logging of transactions to file
- Multichain! Supports both L1 and L2 layers of the protocol simultaneously
- Integrates seamlessly with [hardhat-secure-accounts](https://www.npmjs.com/package/hardhat-secure-accounts)
- Convenience method to create tasks that use GRE

## Usage

#### Example
Import GRE using `import '@graphprotocol/sdk/gre'` on your hardhat config file and then:

```js
// Use L2 governor account to set the L1 token address on the L2 gateway
const { l1, l2 } = hre.graph()

const { GraphToken } = l1.contracts

const { L2GraphTokenGateway } = l2.contracts
const { governor } = await l2.getNamedAccounts()

const tx = L2GraphTokenGateway.connect(governor).setL1TokenAddress(GraphToken.address)
```
__Note__: Project must run hardhat@~2.14.0 due to https://github.com/NomicFoundation/hardhat/issues/1539#issuecomment-1067543942

#### Network selection

GRE supports both the L1 and L2 networks of the Graph Protocol by default. It will use hardhat's network defined via `--network` as the "main" network and then automatically detect which is the appropriate counterpart network in L1 or L2.

Example:

```bash
# L1: goerli and L2: arbitrum-goerli
hh console --network goerli

# L1: mainnet and L2: arbitrum-one
hh console --network arbitrum-one

# L1: mainnet and L2: arbitrum-one > same as previous
hh console --network mainnet
```

#### Configuration

To use GRE you'll need to configure the target networks. That is done via either hardhat's config file using the `networks` [config field](https://hardhat.org/hardhat-runner/docs/config#json-rpc-based-networks) or by passing the appropriate arguments to `hre.graph()` initializer.

__Note__: The "main" network, defined by hardhat's `--network` flag _MUST_ be properly configured for GRE to initialize successfully. It's not necessary to configure the counterpart network if you don't plan on using it.

**Hardhat: Network config**
```js
networks: {
  goerli: { 
    chainId: 5,
    url: `https://goerli.infura.io/v3/123456`
    accounts: {
      mnemonic: 'test test test test test test test test test test test test',
    },
    graphConfig: 'config/graph.goerli.yml'
  },
}
```

Fields:
- **(_REQUIRED_) chainId**: the chainId of the network. This field is not required by hardhat but it's used by GRE to simplify the API.
- **(_REQUIRED_) url**: the RPC endpoint of the network.
- **(_OPTIONAL_) accounts**: the accounts to use on the network. These will be used by the account management functions on GRE.
- **(_OPTIONAL_) graphConfig**: the path to the graph config file for the network.

**Hardhat: Graph config**

Additionally, the plugin adds a new config field to hardhat's config file: `graphConfig`. This can be used used to define defaults for the graph config file.


```js
...
networks: {
...
},
graph: {
  addressBook: 'addresses.json'
  l1GraphConfig: 'config/graph.mainnet.yml'
  l2GraphConfig: 'config/graph.arbitrum-one.yml'
}
...
```

Fields:
- **(_OPTIONAL_) addressBook**: the path to the address book.
- **(_REQUIRED_) l1GraphConfig**: default path to the graph config file for L1 networks. This will be used if the `graphConfig` field is not defined on the network config.
- **(_REQUIRED_) l2GraphConfig**: default path to the graph config file for L2 networks. This will be used if the `graphConfig` field is not defined on the network config.

**Options: Graph initializer**

The GRE initializer also allows you to set the address book and the graph config files like so:
```js
const graph = hre.graph({
  addressBook: 'addresses.json',
  l1GraphConfig: 'config/graph.mainnet.yml'
  l2GraphConfig: 'config/graph.arbitrum-one.yml'
})

// Here graphConfig will apply only to the "main" network given by --network
const graph = hre.graph({
  addressBook: 'addresses.json',
  graphConfig: 'config/graph.mainnet.yml'
})
```

**Config priority**

The path to the graph config and the address book can be set in multiple ways. The plugin will use the following order to determine the path to the graph config file:

1) `hre.graph({ ... })` init parameters `l1GraphConfigPath` and `l2GraphConfigPath`
2) `hre.graph({ ...})` init parameter graphConfigPath (but only for the "main" network)
3) `networks.<NETWORK_NAME>.graphConfig` network config parameter `graphConfig` in hardhat config file
4) `graph.l<X>GraphConfig` graph config parameters `l1GraphConfig` and `l2GraphConfig` in hardhat config file

The priority for the address book is:
1) `hre.graph({ ... })` init parameter `addressBook`
2) `graph.addressBook` graph config parameter `addressBook` in hardhat config file

### Graph task convenience method

GRE accepts a few parameters when being initialized. When using GRE in the context of a hardhat task these parameters would typically be configured as task options. 

In order to simplify the creation of hardhat tasks that will make use of GRE and would require several options to be defined we provide a convenience method: `greTask`. This is a drop in replacement for hardhat's `task` that includes GRE related boilerplate, you can still customize the task as you would do with `task`.

 you avoid having to define GRE's options on all of your tasks.

Here is an example of a task using this convenience method:

```ts
import { greTask } from '../../gre/gre'

greTask('hello-world', 'Say hi!', async (args, hre) => {
  console.log('hello world')
  const graph = hre.graph(args)
})
```

```bash
✗ npx hardhat hello-world --help
Hardhat version 2.10.1

Usage: hardhat [GLOBAL OPTIONS] test-graph [--address-book <STRING>] [--disable-secure-accounts] [--graph-config <STRING>] [--l1-graph-config <STRING>] [--l2-graph-config <STRING>]

OPTIONS:

  --address-book                Path to the address book file.
  --disable-secure-accounts     Disable secure accounts.
  --enable-tx-logging           Enable transaction logging.
  --graph-config                Path to the graph config file for the network specified using --network.
  --l1-graph-config             Path to the graph config file for the L1 network.
  --l2-graph-config             Path to the graph config file for the L2 network.

hello-world: Say hi!

For global options help run: hardhat help
```

### Transaction Logging

By default all transactions executed via GRE will be logged to a file. The file will be created on the first transaction with the following convention `tx-<yyyy-mm-dd>.log`. Here is a sample log file:

```
[2024-01-15T14:33:26.747Z] > Sending transaction: GraphToken.addMinter
[2024-01-15T14:33:26.747Z]    = Sender: 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1
[2024-01-15T14:33:26.747Z]    = Contract: 0x428aAe4Fa354c21600b6ec0077F2a6855C7dcbC8
[2024-01-15T14:33:26.747Z]    = Params: [ 0x05eA50dc2C0389117A067D393e0395ACc32c53b6 ]
[2024-01-15T14:33:26.747Z]    = TxHash: 0xa9096e5f9f9a2208202ac3a8b895561dc3f781fa7e19350b0855098a08d193f7
[2024-01-15T14:33:26.750Z]    ✔ Transaction succeeded!
[2024-01-15T14:33:26.777Z] > Sending transaction: GraphToken.renounceMinter
[2024-01-15T14:33:26.777Z]    = Sender: 0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1
[2024-01-15T14:33:26.777Z]    = Contract: 0x428aAe4Fa354c21600b6ec0077F2a6855C7dcbC8
[2024-01-15T14:33:26.777Z]    = Params: [  ]
[2024-01-15T14:33:26.777Z]    = TxHash: 0x48233b256a1f98cb3fecc3dd48d7f7c0175042142e1ca7b9b1f9fc91169bb588
[2024-01-15T14:33:26.780Z]    ✔ Transaction succeeded!
```

If you want to disable transaction logging you can do so by setting the `enableTxLogging` option to `false` when initializing GRE: ```g=graph({ disableSecureAccounts: true })```

## API

GRE exposes functionality via a simple API:

```js
const graph = hre.graph()

// To access the L1 object
graph.l1

// To access the L2 object
graph.l2
```

The interface for both `l1` and `l2` objects looks like this:

```ts
export interface GraphNetworkEnvironment {
  chainId: number
  contracts: NetworkContracts
  provider: EthersProviderWrapper
  graphConfig: any
  addressBook: AddressBook
  getNamedAccounts: () => Promise<NamedAccounts>
  getTestAccounts: () => Promise<SignerWithAddress[]>
  getDeployer: () => Promise<SignerWithAddress>
}
```

**ChainId**

The chainId of the network.

**Contracts**

Returns an object with all the contracts available in the network. Connects using a provider created with the URL specified in hardhat's network configuration (it doesn't use the usual hardhat `hre.ethers.provider`).

```js
> const graph = hre.graph()

// Print curation default reserve ratio on L1
> await g.l1.contracts.Curation.defaultReserveRatio()
500000
```

**Graph Config**

Returns an object that grants raw access to the YAML parse of the graph config file for the protocol. The graph config file is a YAML file that contains all the parameters with which the protocol was deployed.

> TODO: add better APIs to interact with the graph config file.

**Address Book**

Returns an object that allows interacting with the address book.

```js
> const graph = hre.graph()
> graph.l1.addressBook.getEntry('Curation')
{
  address: '0xE59B4820dDE28D2c235Bd9A73aA4e8716Cb93E9B',
  initArgs: [
    '0x48eD7AfbaB432d1Fc6Ea84EEC70E745d9DAcaF3B',
    '0x2DFDC3e11E035dD96A4aB30Ef67fab4Fb6EC01f2',
    '0x8bEd0a89F18a801Da9dEA994D475DEa74f75A059',
    '500000',
    '10000',
    '1000000000000000000'
  ],
  creationCodeHash: '0x25a7b6cafcebb062169bc25fca9bcce8f23bd7411235859229ae3cc99b9a7d58',
  runtimeCodeHash: '0xaf2d63813a0e5059f63ec46e1b280eb9d129d5ad548f0cdd1649d9798fde10b6',
  txHash: '0xf1b1f0f28b80068bcc9fd6ef475be6324a8b23cbdb792f7344f05ce00aa997d7',
  proxy: true,
  implementation: {
    address: '0xAeaA2B058539750b740E858f97159E6856948670',
    creationCodeHash: '0x022576ab4b739ee17dab126ea7e5a6814bda724aa0e4c6735a051b38a76bd597',
    runtimeCodeHash: '0xc7b1f9bef01ef92779aab0ae9be86376c47584118c508f5b4e612a694a4aab93',
    txHash: '0x400bfb7b6c384363b859a66930590507ddca08ebedf64b20c4b5f6bc8e76e125'
  }
}
```

**Account management: getNamedAccounts**
Returns an object with all the named accounts available in the network. Named accounts are accounts that have special roles in the protocol, they are defined in the graph config file.

```js
> const graph = hre.graph()
> const namedAccounts = await g.l1.getNamedAccounts()
> namedAccounts.governor.address
'0xf1135bFF22512FF2A585b8d4489426CE660f204c'
```

The accounts are initialized from the graph config file but if the correct mnemonic or private key is provided via hardhat network configuration then they will be fully capable of signing transactions. Accounts are already connected to the network provider.

**Account management: getTestAccounts**
Returns an object with accounts which can be used for testing/interacting with the protocol. These are obtained from hardhat's network configuration using the provided mnemonic or private key. Accounts are already connected to the network provider.

**Account management: getDeployer**
Returns an object with the would-be deployer account. The deployer is by convention the first (index 0) account derived from the mnemonic or private key provided via hardhat network configuration. Deployer account is already connected to the network provider.

It's important to note that the deployer is not a named account as it's derived from the provided mnemonic so it won't necessarily match the actual deployer for a given deployment. It's the account that would be used to deploy the protocol with the current configuration. It's not possible at the moment to recover the actual deployer account from a deployed protocol.

**Account management: getWallets**
Returns an object with wallets derived from the mnemonic or private key provided via hardhat network configuration. These wallets are not connected to a provider.

**Account management: getWallet**
Returns a wallet derived from the mnemonic or private key provided via hardhat network configuration that matches a given address. This wallet is not connected to a provider.

#### Integration with hardhat-secure-accounts

[hardhat-secure-accounts](https://www.npmjs.com/package/hardhat-secure-accounts) is a hardhat plugin that allows you to use encrypted keystore files to store your private keys. GRE has built-in support to use this plugin. By default is enabled but can be disabled by setting the `disableSecureAccounts` option to `true` when instantiating the GRE object. When enabled, each time you call any of the account management methods you will be prompted for an account name and password to unlock:

```js
// Without secure accounts
> const graph = hre.graph({ disableSecureAccounts: true })
> const deployer = await g.l1.getDeployer()
> deployer.address
'0xBc7f4d3a85B820fDB1058FD93073Eb6bc9AAF59b'

// With secure accounts
> const graph = hre.graph()
> const deployer = await g.l1.getDeployer()
== Using secure accounts, please unlock an account for L1(goerli)
Available accounts:  goerli-deployer, arbitrum-goerli-deployer, rinkeby-deployer, test-mnemonic
Choose an account to unlock (use tab to autocomplete): test-mnemonic
Enter the password for this account: ************
> deployer.address
'0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1'
```
