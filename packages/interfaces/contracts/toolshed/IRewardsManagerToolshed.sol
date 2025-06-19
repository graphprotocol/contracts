// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || 0.8.27;

import { IRewardsManager } from "../contracts/rewards/IRewardsManager.sol";

interface IRewardsManagerToolshed is IRewardsManager {
    /**
     * @dev Emitted when rewards are assigned to an indexer.
     */
    event RewardsAssigned(address indexed indexer, address indexed allocationID, uint256 amount);

    /**
     * @dev Emitted when rewards are assigned to an indexer.
     * @dev We use the Horizon prefix to change the event signature which makes network subgraph development much easier
     */
    event HorizonRewardsAssigned(address indexed indexer, address indexed allocationID, uint256 amount);

    /**
     * @dev Emitted when rewards are denied to an indexer.
     */
    event RewardsDenied(address indexed indexer, address indexed allocationID);

    /**
     * @dev Emitted when a subgraph is denied for claiming rewards.
     */
    event RewardsDenylistUpdated(bytes32 indexed subgraphDeploymentID, uint256 sinceBlock);

    /**
     * @dev Emitted when the subgraph service is set
     */
    event SubgraphServiceSet(address indexed oldSubgraphService, address indexed newSubgraphService);

    function subgraphService() external view returns (address);
}
