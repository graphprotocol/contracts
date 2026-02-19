# Interface Consolidation Pattern

## Overview

This document describes the refactoring pattern applied across several protocol interfaces to consolidate public function signatures from "toolshed" aggregate interfaces back into the primary public interfaces.

## Problem Statement

The original architecture used two types of interfaces:

1. **Public interfaces** (e.g., `ISubgraphService`, `IRewardsManager`)
   - Core protocol function signatures
   - Used by external contracts and integrations

2. **Toolshed interfaces** (e.g., `ISubgraphServiceToolshed`, `IRewardsManagerToolshed`)
   - Aggregate interfaces for TypeScript type generation
   - Combined multiple interfaces including internal ones
   - Added public storage getters that weren't in the main interface

This created a problem: some genuinely public functions (storage getters, view functions) were only available via the toolshed interfaces, not the primary interfaces. External integrators had to either:
- Import the toolshed interface (confusing - it's meant for internal tooling)
- Manually add function signatures to their code

## Solution

Move all public function signatures from toolshed interfaces into their corresponding primary interfaces. The toolshed interfaces remain as aggregates for type generation but no longer define unique function signatures.

## Commits in This Pattern

| Commit       | Interface Consolidated   |
| ------------ | ------------------------ |
| `f4e134c4`   | `IIssuanceAllocator`     |
| `c9c51155`   | `IRewardsManager`        |
| `10ceafa9`   | `IDisputeManager`        |
| `a2c45622`   | `IAllocationManager`     |
| `23148ef2`   | `IDataServicePausable`   |
| `cf3ad751`   | `ISubgraphService`       |

## Example: ISubgraphService

**Before:** `ISubgraphServiceToolshed` defined these getters:

```solidity
interface ISubgraphServiceToolshed is ISubgraphService, ... {
    function indexers(address indexer) external view returns (string memory url, string memory geoHash);
    function stakeToFeesRatio() external view returns (uint256);
    function curationFeesCut() external view returns (uint256);
    function paymentsDestination(address indexer) external view returns (address);
}
```

**After:** These are now in `ISubgraphService`:

```solidity
interface ISubgraphService is IDataServiceFees {
    // ... existing functions ...

    function indexers(address indexer) external view returns (string memory url, string memory geoHash);
    function stakeToFeesRatio() external view returns (uint256);
    function curationFeesCut() external view returns (uint256);
    function paymentsDestination(address indexer) external view returns (address);
}
```

And `ISubgraphServiceToolshed` becomes a pure aggregate:

```solidity
interface ISubgraphServiceToolshed is
    ISubgraphService,
    IAllocationManager,
    // ... other interfaces ...
{}  // Empty body - no unique definitions
```

## Benefits

1. **Cleaner API surface**: All public functions are in the public interface
2. **Better discoverability**: Integrators find all functions in one place
3. **Reduced confusion**: Toolshed interfaces are clearly marked as internal tooling
4. **Type generation still works**: Toolshed aggregates still produce complete TypeScript types

## Guidelines for Future Development

1. **Public getters** belong in the primary interface, not toolshed
2. **Internal functions** exposed for aggregate typing should stay internal
3. **Toolshed interfaces** should only aggregate, never define unique signatures
4. When adding new public functions, add them to the primary interface first
