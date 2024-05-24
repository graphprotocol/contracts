// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { IDisputeManager } from "../interfaces/IDisputeManager.sol";
import { ISubgraphService } from "../interfaces/ISubgraphService.sol";
import { ITAPCollector } from "@graphprotocol/horizon/contracts/interfaces/ITAPCollector.sol";
import { ICuration } from "@graphprotocol/contracts/contracts/curation/ICuration.sol";

abstract contract Directory {
    ISubgraphService private immutable SUBGRAPH_SERVICE;
    IDisputeManager private immutable DISPUTE_MANAGER;
    ITAPCollector private immutable TAP_COLLECTOR;
    ICuration private immutable CURATION;

    event SubgraphServiceDirectoryInitialized(
        address subgraphService,
        address disputeManager,
        address tapCollector,
        address curation
    );
    error DirectoryNotDisputeManager(address caller, address disputeManager);

    modifier onlyDisputeManager() {
        if (msg.sender != address(DISPUTE_MANAGER)) {
            revert DirectoryNotDisputeManager(msg.sender, address(DISPUTE_MANAGER));
        }
        _;
    }

    constructor(address subgraphService, address disputeManager, address tapCollector, address curation) {
        SUBGRAPH_SERVICE = ISubgraphService(subgraphService);
        DISPUTE_MANAGER = IDisputeManager(disputeManager);
        TAP_COLLECTOR = ITAPCollector(tapCollector);
        CURATION = ICuration(curation);

        emit SubgraphServiceDirectoryInitialized(subgraphService, disputeManager, tapCollector, curation);
    }

    function _subgraphService() internal view returns (ISubgraphService) {
        return SUBGRAPH_SERVICE;
    }

    function _disputeManager() internal view returns (IDisputeManager) {
        return DISPUTE_MANAGER;
    }

    function _tapCollector() internal view returns (ITAPCollector) {
        return TAP_COLLECTOR;
    }

    function _curation() internal view returns (ICuration) {
        return CURATION;
    }
}
