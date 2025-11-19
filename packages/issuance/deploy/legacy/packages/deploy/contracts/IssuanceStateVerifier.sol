// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IIssuanceAllocator } from "@graphprotocol/common/contracts/allocate/IIssuanceAllocator.sol";

/// @title IRewardsManagerState
/// @author Edge & Node
/// @notice Interface for RewardsManager state getter functions
/// @dev Minimal interface for the state verification functions we need
interface IRewardsManagerState {
    /// @notice Returns the current ServiceQualityOracle address
    /// @return The address of the ServiceQualityOracle contract
    function serviceQualityOracle() external view returns (address);

    /// @notice Returns the current IssuanceAllocator address
    /// @return The address of the IssuanceAllocator contract
    function issuanceAllocator() external view returns (address);
}

/// @title IGraphTokenMinter
/// @author Edge & Node
/// @notice Interface for GraphToken minter functions
/// @dev Minimal interface for the minter verification function we need
interface IGraphTokenMinter {
    /// @notice Checks if an account has minter role
    /// @param account The account to check
    /// @return True if the account is a minter, false otherwise
    function isMinter(address account) external view returns (bool);
}

/// @title IssuanceStateVerifier
/// @author Edge & Node
/// @notice Stateless helper contract that asserts issuance system integration state
/// @dev All functions revert if the expected state is not met
contract IssuanceStateVerifier {
    /// @notice Thrown when an address value doesn't match the expected value
    /// @param expected The expected address value
    /// @param actual The actual address value found
    error ValueMismatch(address expected, address actual);

    /// @notice Thrown when a minter role is not granted to the expected address
    /// @param token The GraphToken contract address
    /// @param expectedMinter The address that should have minter role
    error MinterRoleNotGranted(address token, address expectedMinter);

    /// @notice Thrown when a target has no allocation in the IssuanceAllocator
    /// @param target The target address expected to have allocation
    error TargetNotAllocated(address target);

    /// @notice Asserts that RewardsManager has the expected ServiceQualityOracle address set
    /// @dev Reverts with ValueMismatch if the addresses don't match
    /// @param rewardsManager The RewardsManager contract to check
    /// @param expectedSQO The expected ServiceQualityOracle address
    function assertServiceQualityOracleSet(IRewardsManagerState rewardsManager, address expectedSQO) external view {
        address current = rewardsManager.serviceQualityOracle();
        if (current != expectedSQO) revert ValueMismatch(expectedSQO, current);
    }

    /// @notice Asserts that RewardsManager has the expected IssuanceAllocator address set
    /// @dev Reverts with ValueMismatch if the addresses don't match
    /// @param rewardsManager The RewardsManager contract to check
    /// @param expectedIA The expected IssuanceAllocator address
    function assertIssuanceAllocatorSet(IRewardsManagerState rewardsManager, address expectedIA) external view {
        address current = rewardsManager.issuanceAllocator();
        if (current != expectedIA) revert ValueMismatch(expectedIA, current);
    }

    /// @notice Asserts that GraphToken has granted minter role to the expected address
    /// @dev Reverts with MinterRoleNotGranted if the minter role is not granted
    /// @param graphToken The GraphToken contract to check
    /// @param expectedMinter The address that should have minter role
    function assertMinterRole(IGraphTokenMinter graphToken, address expectedMinter) external view {
        bool isMinter = graphToken.isMinter(expectedMinter);
        if (!isMinter) revert MinterRoleNotGranted(address(graphToken), expectedMinter);
    }

    /// @notice Asserts that a target has non-zero allocation in the IssuanceAllocator
    /// @dev Uses IIssuanceAllocator.getTargetAllocation(target) and checks totalAllocationPPM > 0
    /// @param issuanceAllocator The IssuanceAllocator contract to check
    /// @param target The target address expected to have an allocation
    function assertTargetAllocated(IIssuanceAllocator issuanceAllocator, address target) external view {
        IIssuanceAllocator.Allocation memory alloc = issuanceAllocator.getTargetAllocation(target);
        if (alloc.totalAllocationPPM == 0) revert TargetNotAllocated(target);
    }
}

