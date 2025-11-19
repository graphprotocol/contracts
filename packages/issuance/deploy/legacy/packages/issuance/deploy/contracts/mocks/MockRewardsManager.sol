// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockRewardsManager
/// @author Edge & Node
/// @notice Mock contract for testing IssuanceStateVerifier
contract MockRewardsManager {
    address private _serviceQualityOracle;
    address private _issuanceAllocator;

    /// @notice Sets the ServiceQualityOracle address
    /// @param sqo The ServiceQualityOracle address to set
    function setServiceQualityOracle(address sqo) external {
        _serviceQualityOracle = sqo;
    }

    /// @notice Sets the IssuanceAllocator address
    /// @param ia The IssuanceAllocator address to set
    function setIssuanceAllocator(address ia) external {
        _issuanceAllocator = ia;
    }

    /// @notice Returns the current ServiceQualityOracle address
    /// @return The ServiceQualityOracle address
    function serviceQualityOracle() external view returns (address) {
        return _serviceQualityOracle;
    }

    /// @notice Returns the current IssuanceAllocator address
    /// @return The IssuanceAllocator address
    function issuanceAllocator() external view returns (address) {
        return _issuanceAllocator;
    }
}
