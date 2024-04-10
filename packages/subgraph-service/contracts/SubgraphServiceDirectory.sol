// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { ITAPVerifier } from "./interfaces/ITAPVerifier.sol";
import { ISubgraphDisputeManager } from "./interfaces/ISubgraphDisputeManager.sol";

contract SubgraphServiceDirectory {
    ITAPVerifier public immutable tapVerifier;
    ISubgraphDisputeManager public immutable disputeManager;

    event SubgraphServiceDirectoryInitialized(address tapVerifier, address disputeManager);
    error SubgraphServiceDirectoryNotDisputeManager(address caller, address disputeManager);

    modifier onlyDisputeManager() {
        if (msg.sender != address(disputeManager)) {
            revert SubgraphServiceDirectoryNotDisputeManager(msg.sender, address(disputeManager));
        }
        _;
    }

    constructor(address _tapVerifier, address _disputeManager) {
        tapVerifier = ITAPVerifier(_tapVerifier);
        disputeManager = ISubgraphDisputeManager(_disputeManager);

        emit SubgraphServiceDirectoryInitialized(_tapVerifier, _disputeManager);
    }
}
