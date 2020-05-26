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
  yarn build && yarn typechain
  ```

## GNS
**Publishing a subgraph**
```sh
ts-node ./gns.ts 
    --func          publish
    --ipfs          https://api.thegraph.com/ipfs/
    --subgraphName  davesSubgraph  
    --subgraphID    QmdiX6GsbFaz7HDzNxmWCh1oi3bmy19C4te8YSkHbvLbQQ 
    --metadataPath  ./data/metadata.json
```
**Unpublishing a subgraph**
```sh
ts-node ./gns.ts 
    --func          unpublish
    --subgraphName  davesSubgraph
```

**Transferring ownership of a subgraph**
```sh
ts-node ./gns.ts 
    --func          transfer
    --subgraphName  davesSubgraph
    --newOwner      0x7F11E5B7Fe8C04c1E4Ce0dD98aC5c922ECcfA4ed
```

Run the script without arguments for more usage info.

## Graph Token
**Mint**
```sh
ts-node ./graph-token.ts 
    --func          mint
    --account       0x7F11E5B7Fe8C04c1E4Ce0dD98aC5c922ECcfA4ed
    --amount        100
```

**Transfer**
```sh
ts-node ./graph-token.ts 
    --func          transfer
    --account       0x7F11E5B7Fe8C04c1E4Ce0dD98aC5c922ECcfA4ed
    --amount        100
```

**Approve**
```sh
ts-node ./graph-token.ts 
    --func          approve
    --account       0x7F11E5B7Fe8C04c1E4Ce0dD98aC5c922ECcfA4ed
    --amount        100
```

Run the script without arguments for more usage info.
