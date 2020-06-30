# Scripts / CLI
## Setup
These are convenience scripts for interacting with the contracts.

The scripts expect a `.env` file with the following setup:
```
INFURA_KEY= <INSERT_INFURA_API_KEY>
MNEMONIC= <INSERT_12_WORD_MNEMONIC>
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
  - This folder is a CLI that allows for deploying contracts to ethereum networks
- `/contracts`
  - This is a CLI that allows for single calls to interact with deployed contracts
  - It also has `populateData` , which calls all functions the subgraph ingests, so that whenever
    contracts are lauched on a new network, we can quickly test, and get the front end filled
    with data. This data is in `/mockdata`
