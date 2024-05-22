// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRewardsManager } from "@graphprotocol/contracts/contracts/rewards/IRewardsManager.sol";

contract MockRewardsManager is IRewardsManager {
    // -- Config --

    function setIssuancePerBlock(uint256 _issuancePerBlock) external {}

    function setMinimumSubgraphSignal(uint256 _minimumSubgraphSignal) external {}

    function setRewardsIssuer(address _rewardsIssuer, bool _allowed) external {}

    // -- Denylist --

    function setSubgraphAvailabilityOracle(address _subgraphAvailabilityOracle) external {}

    function setDenied(bytes32 _subgraphDeploymentID, bool _deny) external {}

    function setDeniedMany(bytes32[] calldata _subgraphDeploymentID, bool[] calldata _deny) external {}

    function isDenied(bytes32 _subgraphDeploymentID) external view returns (bool) {}

    // -- Getters --

    function getNewRewardsPerSignal() external view returns (uint256) {}

    function getAccRewardsPerSignal() external view returns (uint256) {}

    function getAccRewardsForSubgraph(bytes32 _subgraphDeploymentID) external view returns (uint256) {}

    function getAccRewardsPerAllocatedToken(bytes32 _subgraphDeploymentID) external view returns (uint256, uint256) {}

    function getRewards(address _allocationID) external view returns (uint256) {}

    // -- Updates --

    function updateAccRewardsPerSignal() external returns (uint256) {}

    function takeRewards(address _allocationID) external returns (uint256) {}

    // -- Hooks --

    function onSubgraphSignalUpdate(bytes32 _subgraphDeploymentID) external returns (uint256) {}

    function onSubgraphAllocationUpdate(bytes32 _subgraphDeploymentID) external returns (uint256) {
        return 0;
    }
}