// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || 0.8.27;

// These are needed to get artifacts for toolshed
import "@graphprotocol/contracts/contracts/disputes/IDisputeManager.sol";
import "@graphprotocol/contracts/contracts/discovery/ISubgraphNFT.sol";

// Also for toolshed, solidity version in @graphprotocol/contracts does not support overriding public getters
// in interface file, so we need to amend them here.
import { IServiceRegistry } from "@graphprotocol/contracts/contracts/discovery/IServiceRegistry.sol";
import { IL2Curation } from "@graphprotocol/contracts/contracts/l2/curation/IL2Curation.sol";
import { IGNS } from "@graphprotocol/contracts/contracts/discovery/IGNS.sol";

interface IL2CurationToolshed is IL2Curation {
    function subgraphService() external view returns (address);
}

interface IServiceRegistryToolshed is IServiceRegistry {
    function services(address indexer) external view returns (IServiceRegistry.IndexerService memory);
}

interface IGNSToolshed is IGNS {
    function subgraphNFT() external view returns (address);
}
