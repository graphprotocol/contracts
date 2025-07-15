// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;

interface IRewardsManager {
    /**
     * @dev Stores accumulated rewards and snapshots related to a particular SubgraphDeployment.
     */
    struct Subgraph {
        uint256 accRewardsForSubgraph;
        uint256 accRewardsForSubgraphSnapshot;
        uint256 accRewardsPerSignalSnapshot;
        uint256 accRewardsPerAllocatedToken;
    }

    // -- Config --

    function setIssuancePerBlock(uint256 issuancePerBlock) external;

    function setMinimumSubgraphSignal(uint256 minimumSubgraphSignal) external;

    function setSubgraphService(address subgraphService) external;

    // -- Denylist --

    function setSubgraphAvailabilityOracle(address subgraphAvailabilityOracle) external;

    function setDenied(bytes32 subgraphDeploymentID, bool deny) external;

    function isDenied(bytes32 subgraphDeploymentID) external view returns (bool);

    // -- Getters --

    function getNewRewardsPerSignal() external view returns (uint256);

    function getAccRewardsPerSignal() external view returns (uint256);

    function getAccRewardsForSubgraph(bytes32 subgraphDeploymentID) external view returns (uint256);

    function getAccRewardsPerAllocatedToken(bytes32 subgraphDeploymentID) external view returns (uint256, uint256);

    function getRewards(address rewardsIssuer, address allocationID) external view returns (uint256);

    function calcRewards(uint256 tokens, uint256 accRewardsPerAllocatedToken) external pure returns (uint256);

    // -- Updates --

    function updateAccRewardsPerSignal() external returns (uint256);

    function takeRewards(address allocationID) external returns (uint256);

    // -- Hooks --

    function onSubgraphSignalUpdate(bytes32 subgraphDeploymentID) external returns (uint256);

    function onSubgraphAllocationUpdate(bytes32 subgraphDeploymentID) external returns (uint256);
}
