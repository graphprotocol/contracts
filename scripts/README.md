# Scripts

These are convenience scripts for interacting with the contracts.

The scripts expect the following:

- A `.privkey.txt` file at the root of this repository with the mnemonics for
  your Ethereum account.

- A `.infurakey.txt` file at the root of this repository with an Infura project ID.

- TypeScript bindings need to be generated from the contracts first. Run the
  following at the root of the repository:

  ```sh
  npm run build
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

## Service Registry
**Register**
```sh
ts-node ./service-registry.ts 
    --func          register
    --url           https://172.0.0.1
    --geohash       gbsuve
```

**Unregister**
```sh
ts-node ./service-registry.ts 
    --func          unregister
```

## Curation
**stake**
```sh
ts-node ./curation.ts 
    --func          stake
    --amount        520
```

**redeem**
```sh
ts-node ./curation.ts 
    --func          redeem
    --amount        520
```

## Staking
**stake**
```sh
ts-node ./staking.ts 
    --func          stake
    --amount        520
```

**unstake**
```sh
ts-node ./staking.ts 
    --func          unstake
    --amount        520
```

**withdraw**
```sh
ts-node ./staking.ts 
    --func          withdraw
```