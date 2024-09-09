// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IDisputeManager } from "../interfaces/IDisputeManager.sol";
import { ISubgraphService } from "../interfaces/ISubgraphService.sol";
import { ITAPCollector } from "@graphprotocol/horizon/contracts/interfaces/ITAPCollector.sol";
import { ICuration } from "@graphprotocol/contracts/contracts/curation/ICuration.sol";

/**
 * @title Directory contract
 * @notice This contract is meant to be inherited by {SubgraphService} contract.
 * It contains the addresses of the contracts that the contract interacts with.
 * Uses immutable variables to minimize gas costs.
 */
abstract contract Directory {
    /// @notice The Subgraph Service contract address
    ISubgraphService private immutable SUBGRAPH_SERVICE;

    /// @notice The Dispute Manager contract address
    IDisputeManager private immutable DISPUTE_MANAGER;

    /// @notice The TAP Collector contract address
    /// @dev Required to collect payments via Graph Horizon payments protocol
    ITAPCollector private immutable TAP_COLLECTOR;

    /// @notice The Curation contract address
    /// @dev Required for curation fees distribution
    ICuration private immutable CURATION;

    /**
     * @notice Emitted when the Directory is initialized
     * @param subgraphService The Subgraph Service contract address
     * @param disputeManager The Dispute Manager contract address
     * @param tapCollector The TAP Collector contract address
     * @param curation The Curation contract address
     */
    event SubgraphServiceDirectoryInitialized(
        address subgraphService,
        address disputeManager,
        address tapCollector,
        address curation
    );

    /**
     * @notice Thrown when the caller is not the Dispute Manager
     * @param caller The caller address
     * @param disputeManager The Dispute Manager address
     */
    error DirectoryNotDisputeManager(address caller, address disputeManager);

    /**
     * @notice Checks that the caller is the Dispute Manager
     */
    modifier onlyDisputeManager() {
        require(
            msg.sender == address(DISPUTE_MANAGER),
            DirectoryNotDisputeManager(msg.sender, address(DISPUTE_MANAGER))
        );
        _;
    }

    /**
     * @notice Constructor for the Directory contract
     * @param subgraphService The Subgraph Service contract address
     * @param disputeManager The Dispute Manager contract address
     * @param tapCollector The TAP Collector contract address
     * @param curation The Curation contract address
     */
    constructor(address subgraphService, address disputeManager, address tapCollector, address curation) {
        SUBGRAPH_SERVICE = ISubgraphService(subgraphService);
        DISPUTE_MANAGER = IDisputeManager(disputeManager);
        TAP_COLLECTOR = ITAPCollector(tapCollector);
        CURATION = ICuration(curation);

        emit SubgraphServiceDirectoryInitialized(subgraphService, disputeManager, tapCollector, curation);
    }

    /**
     * @notice Returns the Subgraph Service contract address
     */
    function _subgraphService() internal view returns (ISubgraphService) {
        return SUBGRAPH_SERVICE;
    }

    /**
     * @notice Returns the Dispute Manager contract address
     */
    function _disputeManager() internal view returns (IDisputeManager) {
        return DISPUTE_MANAGER;
    }

    /**
     * @notice Returns the TAP Collector contract address
     */
    function _tapCollector() internal view returns (ITAPCollector) {
        return TAP_COLLECTOR;
    }

    /**
     * @notice Returns the Curation contract address
     */
    function _curation() internal view returns (ICuration) {
        return CURATION;
    }
}
