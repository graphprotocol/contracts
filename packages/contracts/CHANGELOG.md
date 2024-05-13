# @graphprotocol/contracts

## 6.3.0

### Minor Changes

- Remove restriction that prevented closing allocations older than 1 epoch.

## 6.2.1

### Patch Changes

- Round up when calculating curation tax
- Round up when calculating consecutive stake thawing periods

## 6.2.0

### Minor Changes

- Update implementation addresses with GGP 31, 34 and 35

### Patch Changes

- 554af2c: feat(utils): add utility to parse subgraph ids
- Updated dependencies [554af2c]
- Updated dependencies [c5641c5]
  - @graphprotocol/sdk@0.5.0

## 6.1.3

### Patch Changes

- Ensure globbing is enabled in prepack

## 6.1.2

### Patch Changes

- Correctly pass ts file list to tsc in prepack

## 6.1.1

### Patch Changes

- Use prepack to correctly prepare outputs for the published package

## 6.1.0

### Minor Changes

- Introduce changesets for versioning
- Add new staging implementations including GGPs 31, 34 and 35
- Add new testnet implementations including GGPs 31, 34 and 35

### Patch Changes

- Fixes for verifyAll and bridge:send-to-l2 hardhat tasks
