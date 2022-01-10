// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

/// @title Describes subgraph NFT tokens via URI
interface ISubgraphNFTDescriptor {
    /// @notice Produces the URI describing a particular token ID for a Subgraph
    /// @dev Note this URI may be data: URI with the JSON contents directly inlined
    /// @param _minter Address of the allowed minter
    /// @param _tokenId The ID of the subgraph NFT for which to produce a description, which may not be valid
    /// @param _baseURI The base URI that could be prefixed to the final URI
    /// @param _subgraphMetadata Subgraph metadata set for the subgraph
    /// @return The URI of the ERC721-compliant metadata
    function tokenURI(
        address _minter,
        uint256 _tokenId,
        string calldata _baseURI,
        bytes32 _subgraphMetadata
    ) external view returns (string memory);
}
