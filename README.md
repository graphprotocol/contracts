# Graph Protocol Solidity Smart Contracts

![Version Badge](https://img.shields.io/badge/version-1.0.0-lightgrey.svg)
![WIP Badge](https://img.shields.io/badge/status-POC-blue.svg)
[![Build Status](https://travis-ci.com/graphprotocol/contracts.svg?token=wbxCaTb68vuvzoN4HDgt&branch=master)](https://travis-ci.com/graphprotocol/contracts)

## Subgraph

The subgraph can be found https://github.com/graphprotocol/graph-network-subgraph. The addresses
for the subgraph need to be the most up to date. This includes grabbing the latest ABIs from here,
as well as pointing the addresses in the subgraph manifest to the latest addresses. You can find
the latest subgraph addresses below.

There are currently two networks we deploy to - Ropsten, and Ganache. The Ropsten addresses will
change whenever there are updates to the contract, and we need to redeploy. This needs to be
done in sync with deploying a new subgraph. The new GNS should point `thegraph` domain to the
latest subgraph.

We want to also run some test scripts to populate data each time new contracts are deployed (WIP,
Jorge has something that will work for this. Also, running the tests in this repo will populate
data.

You will need two files to deploy anything and run `truffle`, they are `.privkey.txt` and
`.infurakey.txt`. Privkey is a 12 word mneumonic, you should grab you 12 words from metamask, so
that your metamask keys will work in the browser with what you deployed as a governor. The infura
key is just the key you get from the infura website that lets you query up to 100,000 queries a day
for free.

### Current Contract Addresses

See https://github.com/graphprotocol/contracts/blob/master/addresses.json.

### Subgraph Deployment Instructions

#### Ganache

Note, ganache MUST be ran with `ganache-cli -d -i 3859`. `-d` Makes the accounts the same for any
instance of ganache, which allows us to have deterministic contract addresses. Therefore anyone can
use the same subgraph manifest for ganache on their own laptop. `-i 99` is used to make the
network ID constant, which helps with the subgraph. If you update the subgraph, you can just
close ganache and start it up again and you can deploy. If you use the same subgraph ID though and
reset ganche, you will have to drop the DB because it will have old data saved in it, with a new
instance of ganache.

1. Run `ipfs daemon`
2. In a new terminal run postrgres with `pg_ctl -D /usr/local/var/postgres -l logfile start`
3. Create a database with `createdb graph-network-ganache`
4. In a new terminal, run ganache with `ganche-cli -d -i 99`
5. In a new terminal go to the `graph-node` repository start the subgraph with

```
cargo run -p graph-node --release --   \
--postgres-url postgresql://davidkajpust@localhost:5432/graph-network-ganache  \
--ethereum-rpc ganache:http://127.0.0.1:8545   \
--ipfs 127.0.0.1:5001  \
--debug    \
```

6. In a new terminal go to the `graph-network-subgraph` repository, and create the subgraph with
   `yarn create-local` (NOTE - MAKE SURE THE CONTRACT ADDRESSES IN THE MANIFEST ARE SET TO THE
   GANACHE ADDRESSES!)
7. Then deploy it with `yarn deploy-local`

At this point, everything is setup. You can then interact with the contracts through Remix, or
our graph explorer UI, or through our automated scripts. Real automated scripts will be added soon,
but for now you can run `truffle test` and it will run all the tests, and execute transactions,
which will allow the subgraph to store data.

#### Ropsten

(Note we use the graph hosted service right now to deploy to. We do not use the new Dapp explorer UI
to create and deploy subgraphs. It can be found [here](https://staging.thegraph.com/explorer/subgraph/graphprotocol/explorer-dapp)
]. The subgraph is already created, so we will only mention how to update the subgraph here.

1. Deploy new contracts to Ropsten with `truffle deploy --network ropsten`. Truffle stores the
   addresses for networks, so if you are trying to re-deploy you may have to run
   `truffle networks —clean`, and then deploy
2. Get the new contract addresses from the deployment. They are logged in the terminal output from
   deploying. Put these contract addresses into the subgraph manifest
3. Make sure you are a member of `graphprotocol` for the staging explorer application
4. Then make sure you have the right access token for `graphprotocol`. You can set this up with
   `graph auth https://api.thegraph.com/deploy/ <ACCESS_TOKEN>`. You can get it from the dashbaord in the
   UI, just pick `graphprotocol` instead of your own account, and you will see the token.
5. Then in the `graph-network-subgraph` repository, just run `yarn deploy` to update a new version
6. You will also have to update information in the `graph-explorer-dapp` repo. You must update
   the contract addresses in the `.env.development` file, and you need to update the contract addresses
   in the cloud build file
   https://github.com/graphprotocol/graph-explorer-dapp/blob/master/cloudbuild.staging.yaml

At some point in the future we will work on having scripts that will populate data in the subgraph
on ropsten, so we can better test.

## Installation &amp; Deployment of Contracts

1. Install Node.js `^11.0.0`
1. Run `npm install` at project root directory
1. Install and run `testrpc`, `ganache-cli`, or similar blockchain emulator
   - Configure to run on port `8545` or edit `truffle.js` to change the port used by Truffle
1. Install Truffle 5.0.0
   - `npm install -g truffle`
1. Truffle project commands
   - `truffle install` (installs ethPM dependencies)
   - `truffle compile` (compiles without deploying, local blockchain emulator not neccessary)
   - `truffle migrate [--reset] [--compile-all]` (deploys contracts to your local emulator or specified blockchain)
   - `truffle test` (runs tests)
1. See [DEPLOYMENT.md](./DEPLOYMENT.md) for instructions on deploying the contracts to the blockchain.

## Abstract

This repository will contain the Solidity smart contracts needed to facilitate the processes defined in the Product Requirements Document provided by The Graph.
(see: [PRD on Notion](https://www.notion.so/Hybrid-POC-Smart-Contracts-18646757d3644f73bf9fdfb2e98b93eb))

![Imgur](https://i.imgur.com/9uwiie1.png)

## Graph Protocol Solidity Contracts

1. [Graph Token Contract](./contracts/GraphToken.sol)
1. [Staking / Dispute Resolution Contract](./contracts/Staking.sol)
1. [Graph Name Service (GNS) Registry Contract](./contracts/GNS.sol)
1. [Rewards Manager Contract](./contracts/RewardsManager.sol)
1. [Service Registry Contract](./contracts/ServiceRegistry.sol)
1. [Governance Contract](./contracts/Governed.sol)

### Supporting Contracts

1. [MultiSig Contract](./contracts/MultiSigWallet.sol) (by Gnosis)
1. [Detailed, Mintable, Burnable ERC20 Token](./contracts/openzeppelin/) (by Open Zeppelin)
1. [Bonding Curve Formulas](./contracts/bancor/) (by Bancor)
1. [Solidity-Bytes-Utils Library](./installed_contracts/bytes/) (by ConsenSys)

_[See ./contracts/README.md for full list of contracts](./contracts/)_

## Requirement and Implementation Annotations

Each contract includes docstring-like comments with requirements listed at the top of the file.

Example: `@req c01 Any User can stake Graph Tokens to be included as a Curator for a given subgraphId.`

Explanation: The `c01` denotes a section and number for the requirement. `c` in this case stands for `curation` and later in the contract we see `@req s01` used for a `staking` requirement.

Farther down in the code you should see annotations for the implementation of each requirement written as `@imp c01` (and so on). This is meant to be a simple way of defining and matching requirements and their implementations.
