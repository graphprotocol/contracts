// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { ISubgraphService } from "../subgraph-service/ISubgraphService.sol";
import { IOwnable } from "../subgraph-service/internal/IOwnable.sol";
import { IPausable } from "../subgraph-service/internal/IPausable.sol";

interface ISubgraphServiceToolshed is ISubgraphService, IOwnable, IPausable {
    /**
     * @notice Gets the indexer details
     * @param indexer The address of the indexer
     * @return The indexer details
     */
    function indexers(address indexer) external view returns (Indexer memory);

    /**
     * @notice Gets the allocation provision tracker
     * @param indexer The address of the indexer
     * @return The allocation provision tracker
     */
    function allocationProvisionTracker(address indexer) external view returns (uint256);

    /**
     * @notice Gets the stake to fees ratio
     * @return The stake to fees ratio
     */
    function stakeToFeesRatio() external view returns (uint256);

    /**
     * @notice Gets the max POI staleness
     * @return The max POI staleness
     */
    function maxPOIStaleness() external view returns (uint256);

    /**
     * @notice Gets the curation fees cut
     * @return The curation fees cut
     */
    function curationFeesCut() external view returns (uint256);

    /**
     * @notice Gets the pause guardians
     * @param pauseGuardian The address of the pause guardian
     * @return The allowed status of the pause guardian
     */
    function pauseGuardians(address pauseGuardian) external view returns (bool);

    /**
     * @notice Gets the payments destination
     * @param indexer The address of the indexer
     * @return The payments destination
     */
    function paymentsDestination(address indexer) external view returns (address);
}
