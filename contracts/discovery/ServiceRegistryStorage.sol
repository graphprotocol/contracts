// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import "../governance/Managed.sol";

import "./IServiceRegistry.sol";

contract ServiceRegistryV1Storage is Managed {
    // -- State --

    mapping(address => IServiceRegistry.IndexerService) public services;
}
