// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title MockRM
 * @notice Mock RewardsManager for testing
 */
contract MockRM {
    address public rewardsEligibilityOracle;
    address public issuanceAllocator;

    function setRewardsEligibilityOracle(address a) external {
        rewardsEligibilityOracle = a;
    }

    function setIssuanceAllocator(address a) external {
        issuanceAllocator = a;
    }
}
