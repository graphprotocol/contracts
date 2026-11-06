// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface ISubgraphNFTLike {
    function ownerOf(uint256 tokenId) external view returns (address);

    function minter() external view returns (address);

    function setMinter(address minter) external;

    function setTokenDescriptor(address tokenDescriptor) external;

    function tokenURI(uint256 tokenId) external view returns (string memory);
}
