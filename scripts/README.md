# Scripts / CLI
## Setup
These are convenience scripts for interacting with the contracts.

The scripts expect a `.env` file with the following setup:
```
MNEMONIC=
ETHERSCAN_API_KEY=
INFURA_KEY=
ADDRESS_BOOK="addresses.json"
GRAPH_CONFIG=""graph.config.yml""
PROVIDER_URL="http://localhost:8545"
```

Also, run the following:
```sh
npm run build
```

`chmod+x` can be run on the files first, and then you will not need to pass `ts-node` in any of
the script calls.

## Usage
There are two aspects to the CLI right now
- `/cli`
  - This folder is a CLI that allows for deploying contracts to ethereum networks. It uses yargs
  - `cli/cli.ts`
    - This is the main entry point for the CLI
  - `/cli/contracts`
    - This has functions to call the contract functions directly to interact on chain
  - `/cli/scenarios`
    - This is where scenarios live. Scenarios are pre-planned interactions of many txs on chain.
      They are useful for populating data in our contracts to see the subgraph, or to simulate
      real world scenarios on chain
  - There are also single files that provide a command for the cli, which are:
    - `deploy.ts` - helper to deploy a single contract
    - `migrate.ts` - helper to migrate all contracts for a new network on chain
    - `protocol.ts` - set or get with any protocol parameter on any contract
    - `mintTeamTokens.ts` - mint tokens for the whole team for testing purposes
    - `verify.ts` - verify a contract is on chain