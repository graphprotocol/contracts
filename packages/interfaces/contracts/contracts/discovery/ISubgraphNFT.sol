// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface ISubgraphNFT is IERC721 {
    // -- Config --

    function setMinter(address minter) external;

    function setTokenDescriptor(address tokenDescriptor) external;

    function setBaseURI(string memory baseURI) external;

    // -- Actions --

    function mint(address to, uint256 tokenId) external;

    function burn(uint256 tokenId) external;

    function setSubgraphMetadata(uint256 tokenId, bytes32 subgraphMetadata) external;

    function tokenURI(uint256 tokenId) external view returns (string memory);
}
