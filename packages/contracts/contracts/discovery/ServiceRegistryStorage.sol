// SPDX-License-Identifier: GPL-2.0-or-later

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable named-parameters-mapping

pragma solidity ^0.7.6;

import { Managed } from "../governance/Managed.sol";

import { IServiceRegistry } from "@graphprotocol/interfaces/contracts/contracts/discovery/IServiceRegistry.sol";

/**
 * @title Service Registry Storage V1
 * @author Edge & Node
 * @notice Storage contract for the Service Registry
 */
contract ServiceRegistryV1Storage is Managed {
    // -- State --

    /// @notice Mapping of indexer addresses to their service information
    mapping(address => IServiceRegistry.IndexerService) public services;
}
