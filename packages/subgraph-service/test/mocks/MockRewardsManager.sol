// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRewardsManager } from "@graphprotocol/contracts/contracts/rewards/IRewardsManager.sol";

contract MockRewardsManager is IRewardsManager {
    // -- Config --

    function setIssuancePerBlock(uint256) external {}

    function setMinimumSubgraphSignal(uint256) external {}

    function setRewardsIssuer(address, bool) external {}

    // -- Denylist --

    function setSubgraphAvailabilityOracle(address) external {}

    function setDenied(bytes32, bool) external {}

    function setDeniedMany(bytes32[] calldata, bool[] calldata) external {}

    function isDenied(bytes32) external view returns (bool) {}

    // -- Getters --

    function getNewRewardsPerSignal() external view returns (uint256) {}

    function getAccRewardsPerSignal() external view returns (uint256) {}

    function getAccRewardsForSubgraph(bytes32) external view returns (uint256) {}

    function getAccRewardsPerAllocatedToken(bytes32) external view returns (uint256, uint256) {}

    function getRewards(address) external view returns (uint256) {}

    // -- Updates --

    function updateAccRewardsPerSignal() external returns (uint256) {}

    function takeRewards(address) external returns (uint256) {}

    // -- Hooks --

    function onSubgraphSignalUpdate(bytes32) external pure returns (uint256) {}

    function onSubgraphAllocationUpdate(bytes32) external pure returns (uint256) {
        return 0;
    }
}