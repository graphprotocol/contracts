// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "../governance/Managed.sol";

import "./IServiceRegistry.sol";

contract ServiceRegistryV1Storage is Managed {
    // -- State --

    mapping(address => IServiceRegistry.IndexerService) public services;
}
