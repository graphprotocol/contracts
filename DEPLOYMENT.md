## Deploying the Solidity Smart Contracts

### Running

A script in `/scripts/cli/cli.ts` deploys the contracts to the specified network when used with the `migrate` command.
This script accepts multiple commands that you can see using `/scripts/cli/cli.ts --help`

For convenience, the script can be also run with `npm run migrate`.

The migrate command will:

- Read contracts configuration from a file.
- Parse command-line options to select which network to deploy and the wallet to use.
- Check if contracts were already deployed and skip them.
- Deploy the contracts and wait for each transaction to be mined.
- Write an address book file with the deployed contracts data.

NOTE: Please run `npm run build` at least once before running migrate as this command relies on artifacts produced in the compilation process.

### Networks

By default, `npm run migrate` will deploy the contracts to a localhost instance of a development network.

- To deploy to a different network execute `npm run migrate -- -p {providerURL}`.

For example:

```
npm run migrate -- -p https://kovan.infura.io/v3
```

- To deploy using your own wallet execute `npm run migrate -- -m {mnemonic}`.

For example:

```
npm run migrate -- -m "myth like bonus scare over problem client lizard pioneer submit female collect"
```

### Configuration

A configuration file called `graph.config.yml` contains the parameters needed to deploy the contracts. Please edit these params as you see fit.

You can use a different set of configuration options by specifying the file location in the command line:

```
npm run migrate -- -c another-graph.config.yml
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
  governor: &governor "0x90F8bf6A479f320ead074411a4B0e7944Ea8c9C1"
  nodeSignerAddress: &nodeSignerAddress "0x0000000000000000000000000000000000000000"

contracts:
  Curation:
    governor: *governor
    token: "${{GraphToken.address}}"
    reserveRatio: 500000
    minimumCurationStake: "100000000000000000000" # 100 GRT
    __calls:
      - fn: "setWithdrawalFeePercentage"
        withdrawalFeePercentage: 50000
  DisputeManager:
    governor: *governor
    arbitrator: *governor
    token: "${{GraphToken.address}}"
    staking: "${{Staking.address}}"
    minimumDeposit: "100000000000000000000" # 100 GRT
    fishermanRewardPercentage: 1000 # in basis points
    slashingPercentage: 1000 # in basis points
  EpochManager:
    governor: *governor
    lengthInBlocks: 5760 # One day in blocks
  GNS:
    governor: *governor
  GraphToken:
    governor: *governor
    initialSupply: "10000000000000000000000000" # 10000000 GRT
  RewardManager:
    governor: *governor
  Staking:
    governor: *governor
    token: "${{GraphToken.address}}"
    epochManager: "${{EpochManager.address}}"
    __calls:
      - fn: "setCuration"
        curation: "${{Curation.address}}"
      - fn: "setChannelDisputeEpochs"
        channelDisputeEpochs: 1
      - fn: "setMaxAllocationEpochs"
        maxAllocationEpochs: 5
      - fn: "setThawingPeriod"
        thawingPeriod: 20 # in blocks
  MinimumViableMultisig:
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
