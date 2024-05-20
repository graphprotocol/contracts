// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IDataService } from "../interfaces/IDataService.sol";

import { DataServiceV1Storage } from "./DataServiceStorage.sol";
import { GraphDirectory } from "./GraphDirectory.sol";
import { ProvisionManager } from "./utilities/ProvisionManager.sol";

/**
 * @title Implementation of the {IDataService} interface.
 * @dev This implementation provides base functionality for a data service:
 * - GraphDirectory, allows the data service to interact with Graph Horizon contracts
 * - ProvisionManager, provides functionality to manage provisions
 *
 * The derived contract should add functionality that implements the interfaces described in {IDataService}.
 */
abstract contract DataService is GraphDirectory, ProvisionManager, DataServiceV1Storage, IDataService {
    /**
     * @dev Addresses in GraphDirectory are immutables, they can only be set in this constructor.
     * @param controller The address of the Graph Horizon controller contract.
     */
    constructor(address controller) GraphDirectory(controller) {}

    /**
     * @notice Verifies and accepts the provision of a service provider in the {Graph Horizon staking
     * contract}.
     * @dev This internal function is a wrapper around {ProvisionManager-checkAndAcceptProvision}
     * that ensures the event {ProvisionAccepted} is emitted when called from different contexts.
     *
     * Emits a {ProvisionAccepted} event.
     *
     * @param _serviceProvider The address of the service provider.
     */
    function _acceptProvision(address _serviceProvider) internal {
        _checkAndAcceptProvision(_serviceProvider);
        emit ProvisionAccepted(_serviceProvider);
    }
}
