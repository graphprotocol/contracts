// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IDataService } from "./interfaces/IDataService.sol";

import { DataServiceV1Storage } from "./DataServiceStorage.sol";
import { GraphDirectory } from "../utilities/GraphDirectory.sol";
import { ProvisionManager } from "./utilities/ProvisionManager.sol";

/**
 * @title DataService contract
 * @dev Implementation of the {IDataService} interface.
 * @notice This implementation provides base functionality for a data service:
 * - GraphDirectory, allows the data service to interact with Graph Horizon contracts
 * - ProvisionManager, provides functionality to manage provisions
 *
 * The derived contract MUST implement all the interfaces described in {IDataService} and in
 * accordance with the Data Service framework.
 * @dev A note on upgradeability: this base contract can be inherited by upgradeable or non upgradeable
 * contracts.
 * - If the data service implementation is upgradeable, it must initialize the contract via an external
 * initializer function with the `initializer` modifier that calls {__DataService_init} or
 * {__DataService_init_unchained}. It's recommended the implementation constructor to also call
 * {_disableInitializers} to prevent the implementation from being initialized.
 * - If the data service implementation is NOT upgradeable, it must initialize the contract by calling
 * {__DataService_init} or {__DataService_init_unchained} in the constructor. Note that the `initializer`
 * will be required in the constructor.
 * - Note that in both cases if using {__DataService_init_unchained} variant the corresponding parent
 * initializers must be called in the implementation.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
abstract contract DataService is GraphDirectory, ProvisionManager, DataServiceV1Storage, IDataService {
    /**
     * @dev Addresses in GraphDirectory are immutables, they can only be set in this constructor.
     * @param controller The address of the Graph Horizon controller contract.
     */
    constructor(address controller) GraphDirectory(controller) {}

    /// @inheritdoc IDataService
    function getThawingPeriodRange() external view returns (uint64, uint64) {
        return _getThawingPeriodRange();
    }

    /// @inheritdoc IDataService
    function getVerifierCutRange() external view returns (uint32, uint32) {
        return _getVerifierCutRange();
    }

    /// @inheritdoc IDataService
    function getProvisionTokensRange() external view returns (uint256, uint256) {
        return _getProvisionTokensRange();
    }

    /// @inheritdoc IDataService
    function getDelegationRatio() external view returns (uint32) {
        return _getDelegationRatio();
    }

    /**
     * @notice Initializes the contract and any parent contracts.
     */
    function __DataService_init() internal onlyInitializing {
        __ProvisionManager_init_unchained();
        __DataService_init_unchained();
    }

    /**
     * @notice Initializes the contract.
     */
    function __DataService_init_unchained() internal onlyInitializing {}
}
