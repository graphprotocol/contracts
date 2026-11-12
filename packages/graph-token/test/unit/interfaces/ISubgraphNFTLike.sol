// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface ISubgraphNFTLike {
    event MinterUpdated(address minter);
    event TokenDescriptorUpdated(address tokenDescriptor);
    event SubgraphMetadataUpdated(uint256 indexed tokenID, bytes32 subgraphURI);

    function minter() external view returns (address);

    function tokenDescriptor() external view returns (address);

    function ownerOf(uint256 tokenId) external view returns (address);

    function setMinter(address minter) external;

    function setTokenDescriptor(address tokenDescriptor) external;

    function setBaseURI(string memory baseURI) external;

    function mint(address to, uint256 tokenId) external;

    function burn(uint256 tokenId) external;

    function setSubgraphMetadata(uint256 tokenId, bytes32 subgraphMetadata) external;

    function tokenURI(uint256 tokenId) external view returns (string memory);
}
