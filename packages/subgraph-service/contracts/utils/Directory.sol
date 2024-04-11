// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { ITAPVerifier } from "../interfaces/ITAPVerifier.sol";
import { IDisputeManager } from "../interfaces/IDisputeManager.sol";
import { ISubgraphService } from "../interfaces/ISubgraphService.sol";

contract Directory {
    ITAPVerifier public immutable tapVerifier;
    IDisputeManager public immutable disputeManager;
    ISubgraphService public immutable subgraphService;

    event SubgraphServiceDirectoryInitialized(address subgraphService, address tapVerifier, address disputeManager);
    error SubgraphServiceDirectoryNotDisputeManager(address caller, address disputeManager);

    modifier onlyDisputeManager() {
        if (msg.sender != address(disputeManager)) {
            revert SubgraphServiceDirectoryNotDisputeManager(msg.sender, address(disputeManager));
        }
        _;
    }

    constructor(address _subgraphService, address _tapVerifier, address _disputeManager) {
        subgraphService = ISubgraphService(_subgraphService);
        tapVerifier = ITAPVerifier(_tapVerifier);
        disputeManager = IDisputeManager(_disputeManager);

        emit SubgraphServiceDirectoryInitialized(_subgraphService, _tapVerifier, _disputeManager);
    }
}
