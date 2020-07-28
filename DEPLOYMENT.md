## Deploying the Solidity Smart Contracts

### Running

A script in `./scripts/cli/cli.ts` deploys the contracts to the specified network when used with the `migrate` command.

This script accepts multiple commands that you can print using:

```
/scripts/cli/cli.ts --help
```

For convenience, the script can also be used as a buidler command with `buidler migrate` and it can be also run with:

```
npm run migrate
```

The **migrate** command will:

- Read contracts configuration from a file.
- Parse command-line options to select which network to deploy and the wallet to use.
- Check if contracts were already deployed and skip them.
- Deploy the contracts and wait for each transaction to be mined.
- Write an address book file with the deployed contracts data.

The script accepts multiple parameters that allow to override default values, print the available options with:

```
npm run migrate -- --help
```

NOTE: Please run `npm run build` at least once before running migrate as this command relies on artifacts produced in the compilation process.

### Networks

By default, `npm run migrate` will deploy the contracts to a localhost instance of a development network.

To deploy to a different network execute:

```
npm run migrate -- --network {networkName}

# Example
npm run migrate -- --network kovan
```

The network must be configured in the `builder.config.ts` as explained in https://buidler.dev/config/#networks-configuration.

To deploy using your own wallet add the HD Wallet Config to the `builder.config.ts` file according to https://buidler.dev/config/#hd-wallet-config.

### Configuration

A configuration file called `graph.config.yml` contains the parameters needed to deploy the contracts. Please edit these params as you see fit.

You can use a different set of configuration options by specifying the file location in the command line:

```
npm run migrate -- --graph-config another-graph.config.yml
```

Rules:

- Under the `contracts` key every contract configuration is defined by its name.
- Every key under a contract name are parameters sent in the contract constructor in the order they are declared.
- YAML anchors can be used to set common values like \*governor.
- A special key called `__calls` let you define a list of parameters that will be set at the end of all the contracts deployment by calling the function defined in the `fn` key.
- The configuration file can set a parameter to a value read from the AddressBook by using `${{ContractName.AttributeName}}`. For example `${{GraphToken.address}}`.

Example:

```
general:
  arbitrator: &arbitrator "0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1"
  nodeSignerAddress: &nodeSignerAddress "0x0000000000000000000000000000000000000000"

contracts:
  Curation:
    init:
      token: "${{GraphToken.address}}"
      reserveRatio: 500000 # 50% bonding curve reserve ratio parameter
      minimumCurationDeposit: "100000000000000000000" # 100 GRT
    proxy: true
    calls:
      - fn: "setWithdrawalFeePercentage"
        withdrawalFeePercentage: 50000 # 5% fee for redeeming signal
  DisputeManager:
    init:
      arbitrator: *arbitrator
      token: "${{GraphToken.address}}"
      staking: "${{Staking.address}}"
      minimumDeposit: "100000000000000000000" # 100 GRT
      fishermanRewardPercentage: 100000 # in basis points
      slashingPercentage: 50000 # in basis points
  EpochManager:
    init:
      lengthInBlocks: 5760 # One day in blocks
    proxy: true
  GNS:
    init:
      didRegistry: "0xdca7ef03e98e0dc2b855be647c39abe984fcf21b"
      curation: "${{Curation.address}}"
      token: "${{GraphToken.address}}"
  GraphToken:
    init:
      initialSupply: "10000000000000000000000000" # 10000000 GRT
  Staking:
    init:
      token: "${{GraphToken.address}}"
      epochManager: "${{EpochManager.address}}"
    proxy: true
    calls:
      - fn: "setCuration"
        curation: "${{Curation.address}}"
      - fn: "setChannelDisputeEpochs"
        channelDisputeEpochs: 1
      - fn: "setMaxAllocationEpochs"
        maxAllocationEpochs: 5
      - fn: "setThawingPeriod"
        thawingPeriod: 20 # in blocks
  MinimumViableMultisig:
    init:
      node: *nodeSignerAddress
      staking: "${{Staking.address}}"
      CTDT: "${{IndexerCTDT.address}}"
      singleAssetInterpreter: "${{IndexerSingleAssetInterpreter.address}}"
      multiAssetInterpreter: "${{IndexerMultiAssetInterpreter.address}}"
      withdrawInterpreter: "${{IndexerWithdrawInterpreter.address}}"
```

### Address book

After running the migrate script it will print debugging information on the console and the resulting contract information will be saved on the `addresses.json` file.

The upmost key of that file is the **chainID**. This allows to accommodate the deployment information of multiple networks in the same address book.

For each contract deployed, the address book will contain:

- Contract address.
- Constructor arguments.
- Creation code hash.
- Runtime code hash.
- Transaction hash of the deployment.

### Order of deployment

Some contracts require the address from previously deployed contracts. For that reason, the order of deployment is as below:

- EpochManager
- GNS
- GraphToken
- ServiceRegistry
- Curation
- RewardManager
- Staking
- DisputeManager
- IndexerCTDT
- IndexerSingleAssetInterpreter
- IndexerMultiAssetInterpreter
- IndexerWithdrawInterpreter
- MinimumViableMultisig
