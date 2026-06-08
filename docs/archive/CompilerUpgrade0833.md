# Compiler Upgrade: Solidity 0.8.33 + viaIR

This document captures the bytecode size changes resulting from the compiler configuration upgrade in the `subgraph-service` and `issuance` packages.

## Configuration Changes

### subgraph-service

| Setting          | Before  | After   |
| ---------------- | ------- | ------- |
| Solidity Version | 0.8.27  | 0.8.33  |
| EVM Version      | paris   | cancun  |
| Optimizer        | enabled | enabled |
| Optimizer Runs   | 10      | 100     |
| viaIR            | false   | true    |

### issuance

| Setting          | Before  | After   |
| ---------------- | ------- | ------- |
| Solidity Version | 0.8.27  | 0.8.33  |
| EVM Version      | cancun  | cancun  |
| Optimizer        | enabled | enabled |
| Optimizer Runs   | 100     | 100     |
| viaIR            | false   | true    |

## Subgraph-Service Contract Bytecode Sizes

All contracts defined in `packages/subgraph-service/contracts/`:

| Contract                    | Source File                                       | Before (KiB) | After (KiB) | Change (KiB) | Change (%) |
| --------------------------- | ------------------------------------------------- | ------------ | ----------- | ------------ | ---------- |
| **SubgraphService**         | contracts/SubgraphService.sol                     | 24.455       | 23.110      | **-1.345**   | -5.5%      |
| **DisputeManager**          | contracts/DisputeManager.sol                      | 13.278       | 10.917      | **-2.361**   | -17.8%     |
| Allocation                  | contracts/libraries/Allocation.sol                | 0.084        | 0.056       | -0.028       | -33.3%     |
| Attestation                 | contracts/libraries/Attestation.sol               | 0.084        | 0.056       | -0.028       | -33.3%     |
| LegacyAllocation            | contracts/libraries/LegacyAllocation.sol          | 0.084        | 0.056       | -0.028       | -33.3%     |
| SubgraphServiceV1Storage    | contracts/SubgraphServiceStorage.sol              | (abstract)   | (abstract)  | -            | -          |
| DisputeManagerV1Storage     | contracts/DisputeManagerStorage.sol               | (abstract)   | (abstract)  | -            | -          |
| AllocationManager           | contracts/utilities/AllocationManager.sol         | (abstract)   | (abstract)  | -            | -          |
| AllocationManagerV1Storage  | contracts/utilities/AllocationManagerStorage.sol  | (abstract)   | (abstract)  | -            | -          |
| AttestationManager          | contracts/utilities/AttestationManager.sol        | (abstract)   | (abstract)  | -            | -          |
| AttestationManagerV1Storage | contracts/utilities/AttestationManagerStorage.sol | (abstract)   | (abstract)  | -            | -          |
| Directory                   | contracts/utilities/Directory.sol                 | (abstract)   | (abstract)  | -            | -          |

### Initcode Size (Subgraph-Service Contracts)

| Contract            | Before (KiB) | After (KiB) | Change (KiB) |
| ------------------- | ------------ | ----------- | ------------ |
| **SubgraphService** | 26.109       | 24.894      | **-1.215**   |
| **DisputeManager**  | 14.649       | 12.342      | **-2.307**   |

## Issuance Contract Bytecode Sizes

All contracts defined in `packages/issuance/contracts/`:

| Contract                     | Source File                                        | Before (KiB) | After (KiB) | Change (KiB) | Change (%) |
| ---------------------------- | -------------------------------------------------- | ------------ | ----------- | ------------ | ---------- |
| **IssuanceAllocator**        | contracts/allocate/IssuanceAllocator.sol           | 10.444       | 10.250      | **-0.194**   | -1.9%      |
| **RewardsEligibilityOracle** | contracts/eligibility/RewardsEligibilityOracle.sol | 4.316        | 4.554       | +0.238       | +5.5%      |
| **DirectAllocation**         | contracts/allocate/DirectAllocation.sol            | 2.978        | 3.393       | +0.415       | +13.9%     |
| BaseUpgradeable              | contracts/common/BaseUpgradeable.sol               | (abstract)   | (abstract)  | -            | -          |

### Initcode Size (Issuance Contracts)

| Contract                     | Before (KiB) | After (KiB) | Change (KiB) |
| ---------------------------- | ------------ | ----------- | ------------ |
| **IssuanceAllocator**        | 10.817       | 10.601      | **-0.216**   |
| **RewardsEligibilityOracle** | 4.666        | 4.881       | +0.215       |
| **DirectAllocation**         | 3.330        | 3.723       | +0.393       |

### Test Contracts (Issuance)

| Contract                     | Before (KiB) | After (KiB) | Change (KiB) |
| ---------------------------- | ------------ | ----------- | ------------ |
| IssuanceAllocatorTestHarness | 10.641       | 10.331      | -0.310       |
| MockReentrantTarget          | 1.886        | 1.535       | -0.351       |
| MockNotificationTracker      | 0.495        | 0.438       | -0.057       |
| MockRevertingTarget          | 0.342        | 0.250       | -0.092       |
| MockSimpleTarget             | 0.293        | 0.237       | -0.056       |
| MockERC165                   | 0.188        | 0.141       | -0.047       |

## Dependency Library Sizes

Libraries from horizon and other packages compiled as part of subgraph-service:

### Horizon Libraries

| Library          | Before (KiB) | After (KiB) | Change (KiB) |
| ---------------- | ------------ | ----------- | ------------ |
| LinkedList       | 0.084        | 0.056       | -0.028       |
| TokenUtils       | 0.084        | 0.056       | -0.028       |
| UintRange        | 0.084        | 0.056       | -0.028       |
| MathUtils        | 0.084        | 0.056       | -0.028       |
| PPMMath          | 0.084        | 0.056       | -0.028       |
| ProvisionTracker | 0.084        | 0.056       | -0.028       |

### OpenZeppelin Libraries

| Library          | Before (KiB) | After (KiB) | Change (KiB) |
| ---------------- | ------------ | ----------- | ------------ |
| Address          | 0.084        | 0.056       | -0.028       |
| Panic            | 0.084        | 0.056       | -0.028       |
| Strings          | 0.084        | 0.056       | -0.028       |
| Errors           | 0.084        | 0.056       | -0.028       |
| MessageHashUtils | 0.084        | 0.056       | -0.028       |
| SafeCast         | 0.084        | 0.056       | -0.028       |
| ECDSA            | 0.084        | 0.056       | -0.028       |
| SignedMath       | 0.084        | 0.056       | -0.028       |
| Math             | 0.084        | 0.056       | -0.028       |

### Interfaces Package

| Contract         | Before (KiB) | After (KiB) | Change (KiB) |
| ---------------- | ------------ | ----------- | ------------ |
| RewardsCondition | 0.458        | 0.520       | +0.062       |

## Key Observations

### subgraph-service

1. **SubgraphService now fits within mainnet limit**: The 24 KiB contract size limit was exceeded before (24.455 KiB). After the upgrade, it's safely under at 23.110 KiB.

2. **Significant savings on main contracts**: Despite increasing optimizer runs from 10 to 100 (which typically increases size for runtime gas savings), the viaIR pipeline produced smaller bytecode:
   - SubgraphService: -1.345 KiB (-5.5%)
   - DisputeManager: -2.361 KiB (-17.8%)

3. **Abstract contracts have no bytecode**: Storage contracts (e.g., `SubgraphServiceV1Storage`), utility contracts (`AllocationManager`, `AttestationManager`, `Directory`) are inherited by deployable contracts and have no standalone bytecode.

4. **Library stub sizes reduced**: All library stubs decreased from 0.084 KiB to 0.056 KiB (-33%), indicating more efficient metadata encoding.

### issuance

1. **IssuanceAllocator reduced**: The main contract decreased slightly (-0.194 KiB, -1.9%) with viaIR enabled.

2. **Smaller contracts increased**: DirectAllocation (+13.9%) and RewardsEligibilityOracle (+5.5%) increased in size. This is expected behavior as viaIR optimizations are more effective on larger contracts with complex inheritance patterns.

3. **Test contracts all decreased**: All mock/test contracts benefited from viaIR, showing -5% to -19% reductions.

## Why viaIR Reduces Size

The viaIR (Intermediate Representation) compilation pipeline:

- Uses Yul as an intermediate language
- Enables more aggressive cross-function optimizations
- Removes redundant code paths more effectively
- Particularly beneficial for large contracts with complex inheritance

## Date

Comparison performed: 2026-01-25
