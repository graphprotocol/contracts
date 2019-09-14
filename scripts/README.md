# Scripts

These are convenience scripts for interacting with the contracts.

The scripts expect the following:

- `ts-node` to be installed globally on your system. This can be achieved with:

  ```sh
  npm install -g typescript ts-node
  ```

- A `.privkey.txt` file at the root of this repository with the mnemonics for
  your Ethereum account.

- A `.infurakey.txt` file at the root of this repository with an Infura project ID.

- TypeScript bindings need to be generated from the contracts first. Run the
  following at the root of the repository:

  ```sh
  yarn contracts && yarn typechain
  ```

## Set the Graph subgraph ID and bootstrap indexers

```sh
./set-graph-subgraph-id.ts          \
    --subgraph-id <ipfs-hash>       \
    --indexers <addr1>,[<addr2>,...]
```

Run the script without arguments for more usage info.

## Set bootstrap index node URLs

```sh
./set-bootstrap-indexer-url.ts   \
    --indexer <ethereum-address> \
    --url <index-node>
```

Run the script without arguments for more usage info.

## Register a top-level domain

```sh
./register-domain.ts --domain <name>
```

Run the script without arguments for more usage info.

## Create a subgraph (with meta data)

```sh
./create-subgraph.ts           \
    --ipfs <ipfs-node>         \
    --subgraph <subgraph-name> \
    --display-name "..."       \
    ...
```

Run the script without arguments for more usage info.

## Update a subgraph to a new ID

```sh
./update-subgraph-id.ts        \
    --subgraph <subgraph-name> \
    --id <ipfs-hash>
```

Run the script without arguments for more usage info.

## Stake for indexing on a subgraph ID

```sh
./stake-for-indexing.ts       \
    --subgraph-id <ipfs-hash> \
    --amount <number>         # min: 100
```

Run the script without arguments for more usage info.
