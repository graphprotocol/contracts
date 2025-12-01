// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title MockRewardsManager
 * @notice Mock RewardsManager for testing
 */
contract MockRewardsManager {
    address public rewardsEligibilityOracle;
    address public issuanceAllocator;

    function setRewardsEligibilityOracle(address _oracle) external {
        rewardsEligibilityOracle = _oracle;
    }

    function setIssuanceAllocator(address _allocator) external {
        issuanceAllocator = _allocator;
    }
}
