// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.4;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

abstract contract SubgraphNFT is ERC721Upgradeable {
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {}
}
