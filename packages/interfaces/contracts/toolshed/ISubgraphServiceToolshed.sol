// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { ISubgraphService } from "../subgraph-service/ISubgraphService.sol";
import { IOwnable } from "./internal/IOwnable.sol";
import { IPausable } from "./internal/IPausable.sol";
import { ILegacyAllocation } from "../subgraph-service/internal/ILegacyAllocation.sol";
import { IProvisionManager } from "./internal/IProvisionManager.sol";
import { IProvisionTracker } from "./internal/IProvisionTracker.sol";
import { IDataServicePausable } from "../data-service/IDataServicePausable.sol";
import { IMulticall } from "../contracts/base/IMulticall.sol";

interface ISubgraphServiceToolshed is
    ISubgraphService,
    IOwnable,
    IPausable,
    IDataServicePausable,
    ILegacyAllocation,
    IProvisionManager,
    IProvisionTracker,
    IMulticall
{
    /**
     * @notice Gets the indexer details
     * @dev Note that this storage getter actually returns a ISubgraphService.Indexer struct, but ethers v6 is not
     *      good at dealing with dynamic types on return values.
     * @param indexer The address of the indexer
     * @return registeredAt The timestamp when the indexer registered
     * @return url The URL where the indexer can be reached at for queries
     * @return geoHash The indexer's geo location, expressed as a geo hash
     */
    function indexers(
        address indexer
    ) external view returns (uint256 registeredAt, string memory url, string memory geoHash);

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
