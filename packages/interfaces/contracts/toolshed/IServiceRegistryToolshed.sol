// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || 0.8.27;

import { IServiceRegistry } from "../contracts/discovery/IServiceRegistry.sol";

interface IServiceRegistryToolshed is IServiceRegistry {
    event ServiceRegistered(address indexed indexer, string url, string geohash);

    /**
     * @notice Gets the indexer registrationdetails
     * @dev Note that this storage getter actually returns a ISubgraphService.IndexerService struct, but ethers v6 is not
     *      good at dealing with dynamic types on return values.
     * @param indexer The address of the indexer
     * @return url The URL where the indexer can be reached at for queries
     * @return geoHash The indexer's geo location, expressed as a geo hash
     */
    function services(address indexer) external view returns (string memory url, string memory geoHash);
}
