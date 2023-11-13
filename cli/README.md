# CLI

## Setup

These are convenience commands for interacting with the contracts.

The CLI expect a `.env` file with the following setup:

```
MNEMONIC=
ETHERSCAN_API_KEY=
INFURA_KEY=
ADDRESS_BOOK="addresses.json"
GRAPH_CONFIG="config/graph.mainnet.yml"
PROVIDER_URL="http://localhost:8545"
```

Also, run the following to create the proper typescript bindings for each contract:

```sh
yarn build
```

## Usage

Run the CLI with `./cli/cli.ts` from the project root folder.

If will print a help with the available commands and parameters.

## Organization

The CLI is organized around commands and subcommands. These commands are defined in the `commands/` folder.

Under the `commands/` there is one file per general command and a folder called `contracts` holding the commands for particular contract interactions.

- `/cli`
  - This folder is a CLI that allows for deploying contracts to ethereum networks. It uses yargs
  - `/cli/cli.ts`
    - This is the main entry point for the CLI.
  - `/cli/commands/contracts`
    - This has functions to call the contract functions directly to interact on chain.
  - `/cli/commands/scenarios`
    - This is where scenarios live. Scenarios are pre-planned interactions of many txs on chain.
      They are useful for populating data in our contracts to see the subgraph, or to simulate
      real world scenarios on chain
  - There are also single files that provide a command for the CLI, which are:
    - `deploy.ts` - helper to deploy a single contract.
    - `migrate.ts` - helper to migrate all contracts for a new network on chain.
    - `protocol.ts` - list, set or get any protocol parameter on any contract.
    - `airdrop.ts` - distribute tokens to multiple addresses.
    - `verify.ts` - verify a contract is on chain.
    - `upgrade.ts` - helper to upgrade a proxy to use a new implementation.
