// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || 0.8.27;

import { IServiceRegistry } from "../contracts/discovery/IServiceRegistry.sol";

interface IServiceRegistryToolshed is IServiceRegistry {
    function services(address indexer) external view returns (IServiceRegistry.IndexerService memory);
}
