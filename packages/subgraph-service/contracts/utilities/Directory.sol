// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { ITAPVerifier } from "../interfaces/ITAPVerifier.sol";
import { IDisputeManager } from "../interfaces/IDisputeManager.sol";
import { ISubgraphService } from "../interfaces/ISubgraphService.sol";
import { ICuration } from "@graphprotocol/contracts/contracts/curation/ICuration.sol";

abstract contract Directory {
    ITAPVerifier public immutable TAP_VERIFIER;
    IDisputeManager public immutable DISPUTE_MANAGER;
    ISubgraphService public immutable SUBGRAPH_SERVICE;
    ICuration public immutable CURATION;

    event SubgraphServiceDirectoryInitialized(
        address subgraphService,
        address tapVerifier,
        address disputeManager,
        address curation
    );
    error DirectoryNotDisputeManager(address caller, address disputeManager);

    modifier onlyDisputeManager() {
        if (msg.sender != address(DISPUTE_MANAGER)) {
            revert DirectoryNotDisputeManager(msg.sender, address(DISPUTE_MANAGER));
        }
        _;
    }

    constructor(address _subgraphService, address _tapVerifier, address _disputeManager, address _curation) {
        SUBGRAPH_SERVICE = ISubgraphService(_subgraphService);
        TAP_VERIFIER = ITAPVerifier(_tapVerifier);
        DISPUTE_MANAGER = IDisputeManager(_disputeManager);
        CURATION = ICuration(_curation);

        emit SubgraphServiceDirectoryInitialized(_subgraphService, _tapVerifier, _disputeManager, _curation);
    }
}
