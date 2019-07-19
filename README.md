# Graph Protocol Solidity Smart Contracts

![WIP Badge](https://img.shields.io/badge/version-0.0.1-lightgrey.svg)
![WIP Badge](https://img.shields.io/badge/status-wip-yellowgreen.svg)
[![Build Status](https://travis-ci.com/graphprotocol/contracts.svg?token=wbxCaTb68vuvzoN4HDgt&branch=master)](https://travis-ci.com/graphprotocol/contracts)

**Authors**:
 - [Bryant Eisenbach](https://github.com/fubuloubu)
 - [Reuven Etzion](https://github.com/retzion)
 - [Ashoka Finley](https://github.com/shkfnly)
 
## Current Contract Addresses
### Kovan
- GNS.sol - 0x32E7a5bECC129b607D6Cf24CDa2B6F7a202461D8

### Ropsten
- GNS.sol - 0x41bcbb61c3fb0e9ea86330f23b564a8171d9c9d9

## Installation &amp; Deployment
1. Install Node.js `^11.0.0`
1. Run `npm install` at project root directory
1. Install and run `testrpc`, `genache-cli`, or similar blockchain emulator
    - Configure to run on port `8545`
1. Install Truffle 5.0.0
    - `npm install -g truffle`
1. Truffle project commands
    - `truffle install` (installs ethPM dependencies)
    - `truffle compile` (compiles without deploying, local blockchain emulator not neccessary)
    - `truffle migrate [--reset] [--compile-all]` (deploys contracts to your local emulator)
    - `truffle test` (runs tests)

## Abstract
This repository will contain the Solidity smart contracts needed to facilitate the processes defined in the Product Requirements Document provided by The Graph.
(see: [PRD on Notion](https://www.notion.so/Hybrid-POC-Smart-Contracts-18646757d3644f73bf9fdfb2e98b93eb))

![Imgur](https://i.imgur.com/9uwiie1.png)


## Primary Solidity Contracts
1. [Graph DAO](./contracts/Governance.sol)
1. [Graph Token](./contracts/GraphToken.sol)
1. [Staking Contract](./contracts/Staking.sol)
1. Payment Channel (not a contract)
1. Minting Channel (not a contract)
1. [Graph Name Service (GNS) Registry](./contracts/GNS.sol)
1. [Dispute Resolution Contract](./contracts/DisputeManager.sol)
1. [Rewards Manager Contract](./contracts/RewardsManager.sol)
1. [Service Registry](./contracts/ServiceRegistry.sol)

*[See ./contracts/README.md for full list of contracts](./contracts/)*
