# @graphprotocol/interfaces

## 0.6.4

### Patch Changes

- yAdd feesProvisionTracker to subgraph service interface

## 0.6.3

### Patch Changes

- Add LegacyRewardsManager interface

## 0.6.2

### Patch Changes

- Ensure ServiceRegistry loads the correct interface

## 0.6.1

### Patch Changes

- Add ServiceRegistered to LegacyServiceRegistry interface

## 0.6.0

### Minor Changes

- Updated indexer struct and function signature

## 0.5.2

### Patch Changes

- fix: add missing nextAccountSeqID and multicall to IL2GNSToolshed interface

## 0.5.1

### Patch Changes

- Fix export conditions order to resolve Next.js import errors

## 0.5.0

### Minor Changes

- Add vesting interfaces for Horizon protocol
  - Add IGraphTokenLockWallet base interface for core vesting functionality
  - Add IGraphTokenLockWalletToolshed interface with Horizon protocol interactions
  - Include functions for stake management, provision management, delegation, and configuration
  - Support both current and legacy withdrawDelegated signatures for backward compatibility

## 0.4.0

### Minor Changes

- Add ethers v5 type generation to interfaces package

## 0.3.0

### Minor Changes

- Add wagmi type generation for interfaces package

## 0.2.5

### Patch Changes

- fbe38f9: Add ICuration to L2Curation interface
- Add missing events to SubgraphService and RewardsManager interfaces

## 0.2.4

### Patch Changes

- Ensure latest build is published to npm

## 0.2.3

### Patch Changes

- Add missing interfaces to SubgraphService and ServiceRegistry contracts

## 0.2.2

### Patch Changes

- Ensure dist files are published to NPM

## 0.2.1

### Patch Changes

- Make interfaces package public

## 0.2.0

### Minor Changes

- Extracted contract interfaces into its own package
