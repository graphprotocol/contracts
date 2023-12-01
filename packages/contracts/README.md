![License: GPL](https://img.shields.io/badge/license-GPLv2-blue)
![Version Badge](https://img.shields.io/badge/version-1.14.0-lightgrey.svg)
![CI Status](https://github.com/graphprotocol/contracts/actions/workflows/npmtest.yml/badge.svg)
[![codecov](https://codecov.io/gh/graphprotocol/contracts/branch/dev/graph/badge.svg?token=S8JWGR9SBN)](https://codecov.io/gh/graphprotocol/contracts)

# Graph Protocol Contracts

The Graph Protocol Smart Contracts are a set of Solidity contracts that exist on the Ethereum Blockchain. The contracts enable an open and permissionless decentralized network that coordinates [Graph Nodes](https://github.com/graphprotocol/graph-node) to Index any subgraph that is added to the network. Graph Nodes then provide queries to users for those Subgraphs. Users pay for queries with the Graph Token (GRT).

The protocol allows Indexers to Stake, Delegators to Delegate, and Curators to Signal on Subgraphs. The Signal informs Indexers which Subgraphs they should index.

You can learn more by heading to [the documentation](https://thegraph.com/docs/about/introduction), or checking out some of the [blog posts on the protocol](https://thegraph.com/blog/the-graph-network-in-depth-part-1).

# Contracts

The contracts are upgradable, following the [Open Zeppelin Proxy Upgrade Pattern](https://docs.openzeppelin.com/upgrades-plugins/1.x/proxies). Each contract will be explained in brief detail below.

**_Curation_**

> Allows Curators to Signal GRT towards a Subgraph Deployment they want indexed on The Graph. Curators are often Subgraph Developers, but anyone can participate. Curators also receive a portion of the query fees that are earned on the Subgraph. Signaled GRT goes into a bonding curve, which returns a Graph Curation Share (GCS) to the Curator.

**_Graph Name Service (GNS)_**

> Wraps around the Curation contract to provide pooling of Curator Signaled tokens towards a single Subgraph. This allows an owner to deploy a Subgraph, and upgrade their Subgraph to a new version. The upgrade will move all Curator tokens to a new Subgraph Deployment with a new bonding curve.

**_Service Registry_**

> Allows Indexers to tell the network the location of their node. This allows end users to choose a node close to themselves, lowering the latency for queries.

**_Dispute Manager_**

> Provides a way for Indexers to be slashed or incorrect or malicious behaviour. There are two types of disputes: _Query Disputes_ and _Indexing Disputes_.

**_Epoch Manager_**

> Keeps track of protocol Epochs. Epochs are configured to be a certain block length, which is configurable by The Governor.

**_Controller_**

> The Controller is a contract that has a registry of all protocol contract addresses. It also is the owner of all the contracts. The owner of the Controller is The Governor, which makes The Governor the address that can configure the whole protocol. The Governor is [The Graph Council](https://thegraph.com/blog/introducing-the-graph-council).

**_Rewards Manager_**

> Tracks how inflationary GRT rewards should be handed out. It relies on the Curation contract and the Staking contract. Signaled GRT in Curation determine what percentage of inflationary tokens go towards each subgraph. Each Subgraph can have multiple Indexers Staked on it. Thus, the total rewards for the Subgraph are split up for each Indexer based on much they have Staked on that Subgraph.

**_Staking_**

> The Staking contract allows Indexers to Stake on Subgraphs. Indexers Stake by creating Allocations on a Subgraph. It also allows Delegators to Delegate towards an Indexer. The contract also contains the slashing functionality.

**_Graph Token_**

> An ERC-20 token (GRT) that is used as a work token to power the network incentives. The token is inflationary.

# NPM package

The [NPM package](https://www.npmjs.com/package/@graphprotocol/contracts) contains contract interfaces and addresses for the testnet and mainnet. It also contains [typechain](https://github.com/ethereum-ts/TypeChain) generated objects to easily interact with the contracts. This allows for anyone to install the package in their repository and interact with the protocol. It is updated and released whenever a change to the contracts occurs.

```
yarn add @graphprotocol/contracts
```

# Contract Addresses

The testnet runs on Goerli, while mainnet is on Ethereum Mainnet. The addresses for both of these can be found in `./addresses.json`.

# Local Setup

To setup the contracts locally, checkout the `dev` branch, then run:

```bash
yarn
yarn build
```

# Testing

For testing details see [TESTING.md](./TESTING.md).

# Deploying Contracts

In order to run deployments, see [DEPLOYMENT.md](./DEPLOYMENT.md).

# Interacting with the contracts

There are three ways to interact with the contracts through this repo:

### Hardhat

The most straightforward way to interact with the contracts is through the hardhat console. We have extended the hardhat runtime environment to include all of the contracts. This makes it easy to run the console with autocomplete for all contracts and all functions. It is a quick and easy way to read and write to the contracts.

```
# A console to interact with testnet contracts
npx hardhat console --network goerli
```

### Hardhat Tasks

There are hardhat tasks under the `/tasks` folder. Most tasks are for complex queries to get back data from the protocol.

### CLI

There is a CLI that can be used to read or write to the contracts. It includes scripts to help with deployment.

## Environment

When running the Hardhat console or tasks you can set what network and accounts to use when sending transactions.

### Network

Selecting a network requires just passing `--network <name>` when running Hardhat. It's important that the network exists in the Hardhat configuration file.

_There is a special network called `localhost` that connects it to a node running on localhost._

### Accounts

The accounts used depends on a few environment variables:

- If MNEMONIC is set you will have available the set of addresses derived from the seed.
- If PRIVATE_KEY is set, just that account is imported. MNEMONIC always takes precedence over PRIVATE_KEY.
- If no MNEMONIC or PRIVATE_KEY is set it will use the remote accounts from the provider node.
- You can always get an account using `ethers.getSigner(<address>)`

Considerations when forking a chain:

- When running on the `localhost` network it will use by default a deterministic seed for testing purposes. If you want to connect to a local node that is forking while retaining the capability to impersonate accounts or use local accounts you need to set the FORK=true environment variable.

# Copyright

Copyright &copy; 2021 The Graph Foundation

Licensed under [GPL license](LICENSE).
