// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title Subgraph NFT Interface
 * @author Edge & Node
 * @notice Interface for the Subgraph NFT contract that represents subgraph ownership
 */
interface ISubgraphNFT is IERC721 {
    // -- Config --

    /**
     * @notice Set the minter allowed to perform actions on the NFT
     * @dev Minter can mint, burn and update the metadata
     * @param _minter Address of the allowed minter
     */
    function setMinter(address _minter) external;

    /**
     * @notice Set the token descriptor contract
     * @dev Token descriptor can be zero. If set, it must be a contract
     * @param _tokenDescriptor Address of the contract that creates the NFT token URI
     */
    function setTokenDescriptor(address _tokenDescriptor) external;

    /**
     * @notice Set the base URI
     * @dev Can be set to empty
     * @param _baseURI Base URI to use to build the token URI
     */
    function setBaseURI(string memory _baseURI) external;

    // -- Actions --

    /**
     * @notice Mint `_tokenId` and transfers it to `_to`
     * @dev `tokenId` must not exist and `to` cannot be the zero address
     * @param _to Address receiving the minted NFT
     * @param _tokenId ID of the NFT
     */
    function mint(address _to, uint256 _tokenId) external;

    /**
     * @notice Burn `_tokenId`
     * @dev The approval is cleared when the token is burned
     * @param _tokenId ID of the NFT
     */
    function burn(uint256 _tokenId) external;

    /**
     * @notice Set the metadata for a subgraph represented by `_tokenId`
     * @dev `_tokenId` must exist
     * @param _tokenId ID of the NFT
     * @param _subgraphMetadata IPFS hash for the metadata
     */
    function setSubgraphMetadata(uint256 _tokenId, bytes32 _subgraphMetadata) external;

    /**
     * @notice Returns the Uniform Resource Identifier (URI) for `_tokenId` token
     * @param _tokenId ID of the NFT
     * @return The URI for the token
     */
    function tokenURI(uint256 _tokenId) external view returns (string memory);
}
