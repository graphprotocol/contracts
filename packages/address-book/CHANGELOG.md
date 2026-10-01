# @graphprotocol/address-book

## 1.4.0

### Minor Changes

- Mainnet upgrade on Arbitrum One: promote the fixed SubgraphService implementation (0x09a72545d2040dc6ac3686631daff113e492f8ea, rejects the SubgraphService itself as a payments destination) and the fixed L2GNS implementation (0xa3946606960eee45c9b855de8d3cd30b9c875c34, adds slippage protection to publishNewVersion).

## 1.3.0

### Minor Changes

- GIP-0088 mainnet activation on Arbitrum One: promote upgraded implementations for RewardsManager, SubgraphService, HorizonStaking, L2Curation, DisputeManager and PaymentsEscrow, and add the new IssuanceAllocator, Rewards Eligibility Oracle (A/B/Mock), DefaultAllocation, ReclaimedRewards, DirectAllocation implementation and RecurringCollector/RecurringAgreementManager addresses (Arbitrum One + Arbitrum Sepolia).

## 1.2.0

### Minor Changes

- Upgraded Rewards Manager and Subgraph Service with Rewards Eligibility Oracle and rewards reclaiming.

## 1.1.0

### Minor Changes

- Graph Horizon phase 3 mainnet deployment

## 1.0.1

### Patch Changes

- Fix L2Curation implementation address in subgraph service address book.

## 1.0.0

### Major Changes

- Deploy horizon to testnet

## 0.1.0

### Minor Changes

- Initial release of @graphprotocol/address-book

  This package provides contract addresses for The Graph Protocol:
  - Horizon protocol addresses
  - Subgraph Service addresses
  - Automatic symlink handling for publishing
