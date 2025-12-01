// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IRewardsManager
 * @notice Minimal interface for RewardsManager used in tests
 */
interface IRewardsManager {
    function rewardsEligibilityOracle() external view returns (address);
    function issuanceAllocator() external view returns (address);
    function setRewardsEligibilityOracle(address _rewardsEligibilityOracle) external;
    function setIssuanceAllocator(address _issuanceAllocator) external;
}
