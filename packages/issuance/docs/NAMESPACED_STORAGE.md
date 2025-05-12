# Namespaced Storage Pattern (ERC-7201)

This document explains the namespaced storage pattern used in the issuance project, which follows the [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) standard.

## Overview

The namespaced storage pattern provides better isolation between different contracts in the inheritance chain, reducing the risk of storage collisions. This is particularly important for upgradeable contracts.

## Key Benefits

1. **Better Storage Isolation**: Each contract has its own isolated storage namespace.
2. **Safer Upgrades**: Adding new state variables doesn't require managing storage gaps.
3. **Clearer Organization**: All state variables for a contract are grouped together in a struct.
4. **Compatibility with OpenZeppelin**: OpenZeppelin contracts already use this pattern.
5. **Simplified Architecture**: No need for separate storage contracts.

## Implementation Pattern

The issuance project uses a script-based approach to implement namespaced storage. This approach provides a standardized way to calculate storage slots and generate code templates.

### Standard Pattern

All contracts in the issuance project follow this pattern for implementing namespaced storage:

```solidity
contract MyContract is BaseUpgradeable {
    // -- Namespaced Storage --

    /// @custom:storage-location erc7201:graphprotocol.storage.MyContract
    struct MyContractData {
        // State variables go here
        uint256 someValue;
        mapping(address => bool) someMapping;
        // ...
    }

    function _getMyContractStorage() private pure returns (MyContractData storage $) {
        // This value was calculated using: node scripts/calculate-storage-locations.js --contract MyContract
        assembly {
            $.slot := 0x123456... // Pre-calculated value
        }
    }

    // Rest of the contract implementation...
}
```

### Generate Namespaced Storage Code

We provide a script to generate namespaced storage code. This script calculates the storage slot and generates a complete template for your contract:

```bash
node scripts/calculate-storage-locations.js --contract MyContract
```

This will generate the following output:

```text
Contract Name: MyContract
Namespace: graphprotocol.storage.MyContract
Storage Location: 0x123456...

Solidity code:
/// @custom:storage-location erc7201:graphprotocol.storage.MyContract
struct MyContractData {
    // Add your storage variables here
}

function _getMyContractStorage() private pure returns (MyContractData storage $) {
    // This value was calculated using: node scripts/calculate-storage-locations.js --contract MyContract
    assembly {
        $.slot := 0x123456...
    }
}
```

You can also calculate just the storage location using:

```bash
node scripts/calculate-storage-locations.js "graphprotocol.storage.MyContract"
```

### Access Storage Variables

```solidity
function setValue(uint256 _value) internal {
    MyContractData storage $ = _getMyContractStorage();
    $.someValue = _value;
}

function getValue() internal view returns (uint256) {
    MyContractData storage $ = _getMyContractStorage();
    return $.someValue;
}
```

## Public Accessors

Since state variables inside the storage struct can't be declared as `public`, you need to create explicit getter functions:

```solidity
function someValue() public view returns (uint256) {
    return _getMyContractStorage().someValue;
}
```

## Naming Conventions

1. **Namespace**: Use `graphprotocol.storage.ContractName` as the namespace.
2. **Storage Struct**: Name it `ContractNameData`.
3. **Getter Function**: Name it `_getContractNameStorage()`.

## Example from the Issuance Project

Here's how we implement namespaced storage in the IssuanceAllocator contract:

```solidity
contract IssuanceAllocator is BaseUpgradeable, IIssuanceAllocator {
    using Address for address;

    // -- Namespaced Storage --

    struct AllocationTarget {
        uint256 allocation; // In PPM (parts per million)
        bool exists; // Whether this target exists
        bool isSelfMinter; // Whether this target is a self-minting contract
    }

    /// @custom:storage-location erc7201:graphprotocol.storage.IssuanceAllocator
    struct IssuanceAllocatorData {
        // Total issuance per block
        uint256 issuancePerBlock;

        // Last block when issuance was distributed
        uint256 lastIssuanceBlock;

        // Allocation targets
        mapping(address => AllocationTarget) allocationTargets;
        address[] targetAddresses;

        // Total active allocation (can be less than PPM but never more)
        uint256 totalActiveAllocation;
    }

    /**
     * @dev Returns the storage struct for IssuanceAllocator
     */
    function _getIssuanceAllocatorStorage() private pure returns (IssuanceAllocatorData storage $) {
        // This value was calculated using: node scripts/calculate-storage-locations.js --contract IssuanceAllocator
        assembly {
            $.slot := 0x2d39b85bacae9509bd6a8a34a4de8c9bb5dbc76a31598e9bea496cdec9ff0100
        }
    }

    // Rest of the contract implementation...
}
```

## Adding New State Variables

When you need to add new state variables to a contract:

1. Add them to the storage struct.
2. Create getter functions for any variables that need to be publicly accessible.
3. Update your code to access the variables through the storage struct.

Example:

```solidity
/// @custom:storage-location erc7201:graphprotocol.storage.DirectAllocation
struct DirectAllocationData {
    bool initialized;
    address manager; // New variable
    uint256 lastDistributionBlock; // New variable
}

// Add getter functions
function manager() public view returns (address) {
    return _getDirectAllocationStorage().manager;
}

function lastDistributionBlock() public view returns (uint256) {
    return _getDirectAllocationStorage().lastDistributionBlock;
}
```

## Conclusion

The namespaced storage pattern provides better storage isolation and makes upgrades safer. By using a standardized approach with our script-based tools, we've made it easy to implement namespaced storage consistently across the issuance project.
