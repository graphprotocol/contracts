// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "../discovery/IGNS.sol";

/// @title Describes subgraph NFT tokens via URI
interface ISubgraphNFTDescriptor {
    /// @notice Produces the URI describing a particular token ID for a Subgraph
    /// @dev Note this URI may be a data: URI with the JSON contents directly inlined
    /// @param _gns GNS contract that holds the Subgraph data
    /// @param _subgraphID The ID of the subgraph NFT for which to produce a description, which may not be valid
    /// @return The URI of the ERC721-compliant metadata
    function tokenURI(IGNS _gns, uint256 _subgraphID) external view returns (string memory);
}
