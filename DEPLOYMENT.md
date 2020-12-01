## Deploying the Solidity Smart Contracts

### Running

A CLI in `cli/cli.ts` deploys the contracts to the specified network when used with the `migrate` command.

This script accepts multiple commands that you can print using:

```
cli/cli.ts --help
```

For convenience, the script can also be used as a hardhat command with `hardhat migrate` and it can be also run with:

```
npm run deploy
```

The **migrate** command will:

- Read contracts configuration from a file.
- Parse command-line options to select which network to deploy and the wallet to use.
- Check if contracts were already deployed and skip them.
- Deploy the contracts and wait for each transaction to be mined.
- Write an address book file with the deployed contracts data.

The script accepts multiple parameters that allow to override default values, print the available options with:

```
npm run deploy -- --help
```

NOTE: Please run `npm run build` at least once before running migrate as this command relies on artifacts produced in the compilation process.

### Networks

By default, `npm run deploy` will deploy the contracts to a localhost instance of a development network.

To deploy to a different network execute:

```
npm run deploy -- --network {networkName}

# Example
npm run deploy -- --network kovan
```

The network must be configured in the `hardhat.config.ts` as explained in https://hardhat.org/config.

To deploy using your own wallet add the HD Wallet Config to the `hardhat.config.ts` file according to https://hardhat.org/config/#hd-wallet-config.

### Configuration

A configuration file called `graph.config.yml` contains the parameters needed to deploy the contracts. Please edit these params as you see fit.

You can use a different set of configuration options by specifying the file location in the command line:

```
npm run deploy -- --graph-config another-graph.config.yml
```

Rules:

- Under the `contracts` key every contract configuration is defined by its name.
- Every key under a contract name are parameters sent in the contract constructor in the order they are declared.
- YAML anchors can be used to set common values like \*governor.
- A special key called `__calls` let you define a list of parameters that will be set at the end of all the contracts deployment by calling the function defined in the `fn` key.
- The configuration file can set a parameter to a value read from the AddressBook by using `${{ContractName.AttributeName}}`. For example `${{GraphToken.address}}`.

Example:

[https://github.com/graphprotocol/contracts/blob/master/graph.config.yml](https://github.com/graphprotocol/contracts/blob/master/graph.config.yml)

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

- Controller
- EpochManager
- GNS
- GraphToken
- ServiceRegistry
- Curation
- RewardManager
- Staking
- DisputeManager

### Deploying a new testnet

1. Make sure contracts are up to date as you please.
2. `npm run deploy-rinkeby` to deploy to Rinkeby. This will create new contracts with new addresses in `addresses.json`.
3. Update the `package.json` and `package-lock.json` files with the new package version and publish a new npm package with `npm publish`. You can dry-run the files to be uploaded by running `npm publish --dry-run`.
4. Merge this update into master, branch off and save for whatever version of the testnet is going on, and then tag this on the github repo, pointing to your branch (ex. at `testnet-phase-1` branch). This way we can always get the contract code for testnet, while continuing to do work on mainnet.
5. Pull the updated package into the subgraph, and other apps that depend on the package.json.
6. Send tokens to the whole team with `./cli/cli.ts transferTeamTokens --amount 10000000`

### Updating NPM packages and tagging on github and other testnet tasks

If you are deploying the testnet, remember to deploy a new GDAI and GSR, as you
don't want to re-use the previous GSR. Remember to build the contracts.

```
./cli/cli.ts deploy --contract GDAI
./cli/cli.ts deploy --contract GSRManager --init 1000000001547125958,<GDAI_ADDR>
```

Remember to deploy the uniswap pool. And to set the GSRManager in the GDAI contract.

Please remember to rename the Graph Token and GDAI symbols for the appropriate testnet or mainnet
configuration.

Make sure to release an NPM package with the correct name for the release, as well as a github tag
with the exact same name. Remember to check any manual addresses that must be added to the
`addresses.json`. Make sure to deploy a new subgraph and ensure it is hooked up correctly.