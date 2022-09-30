// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.16;

import { Managed } from "../governance/Managed.sol";

import { IServiceRegistry } from "./IServiceRegistry.sol";

contract ServiceRegistryV1Storage is Managed {
    // -- State --

    mapping(address => IServiceRegistry.IndexerService) public services;
}
