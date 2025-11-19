// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockRewardsManager
/// @author Edge & Node
/// @notice Mock contract for testing IssuanceStateVerifier
contract MockRewardsManager {
    address private _rewardsEligibilityOracle;
    address private _issuanceAllocator;

    /// @notice Sets the RewardsEligibilityOracle address
    /// @param reo The RewardsEligibilityOracle address to set
    function setRewardsEligibilityOracle(address reo) external {
        _rewardsEligibilityOracle = reo;
    }

    /// @notice Sets the IssuanceAllocator address
    /// @param ia The IssuanceAllocator address to set
    function setIssuanceAllocator(address ia) external {
        _issuanceAllocator = ia;
    }

    /// @notice Returns the current RewardsEligibilityOracle address
    /// @return The RewardsEligibilityOracle address
    function rewardsEligibilityOracle() external view returns (address) {
        return _rewardsEligibilityOracle;
    }

    /// @notice Returns the current IssuanceAllocator address
    /// @return The IssuanceAllocator address
    function issuanceAllocator() external view returns (address) {
        return _issuanceAllocator;
    }
}
