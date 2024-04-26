// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { ITAPVerifier } from "../interfaces/ITAPVerifier.sol";
import { IDisputeManager } from "../interfaces/IDisputeManager.sol";
import { ISubgraphService } from "../interfaces/ISubgraphService.sol";
import { ICuration } from "@graphprotocol/contracts/contracts/curation/ICuration.sol";

abstract contract Directory {
    ITAPVerifier public immutable tapVerifier;
    IDisputeManager public immutable disputeManager;
    ISubgraphService public immutable subgraphService;
    ICuration public immutable curation;

    event SubgraphServiceDirectoryInitialized(
        address subgraphService,
        address tapVerifier,
        address disputeManager,
        address curation
    );
    error DirectoryNotDisputeManager(address caller, address disputeManager);

    modifier onlyDisputeManager() {
        if (msg.sender != address(disputeManager)) {
            revert DirectoryNotDisputeManager(msg.sender, address(disputeManager));
        }
        _;
    }

    constructor(address _subgraphService, address _tapVerifier, address _disputeManager, address _curation) {
        subgraphService = ISubgraphService(_subgraphService);
        tapVerifier = ITAPVerifier(_tapVerifier);
        disputeManager = IDisputeManager(_disputeManager);
        curation = ICuration(_curation);

        emit SubgraphServiceDirectoryInitialized(_subgraphService, _tapVerifier, _disputeManager, _curation);
    }
}
