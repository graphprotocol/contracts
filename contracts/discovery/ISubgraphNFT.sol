// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface ISubgraphNFT is IERC721 {
    // -- Config --

    function setMinter(address _minter) external;

    function setTokenDescriptor(address _tokenDescriptor) external;

    function setBaseURI(string memory _baseURI) external;

    // -- Actions --

    function mint(address _to, uint256 _tokenId) external;

    function burn(uint256 _tokenId) external;

    function setSubgraphMetadata(uint256 _tokenId, bytes32 _subgraphMetadata) external;

    function tokenURI(uint256 _tokenId) external view returns (string memory);
}
