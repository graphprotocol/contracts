// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { Managed } from "../governance/Managed.sol";

import { IServiceRegistry } from "./IServiceRegistry.sol";

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
