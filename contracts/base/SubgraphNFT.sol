// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import "./ISubgraphNFTDescriptor.sol";

abstract contract SubgraphNFT is ERC721Upgradeable {
    ISubgraphNFTDescriptor public tokenDescriptor;

    // -- Events --

    event TokenDescriptorUpdated(address tokenDescriptor);

    // -- Functions --

    /**
     * @dev Initializes the contract by setting a `name`, `symbol` and `descriptor` to the token collection.
     */
    function __SubgraphNFT_init(address _tokenDescriptor) internal initializer {
        __ERC721_init("Subgraph", "SG");
        _setTokenDescriptor(address(_tokenDescriptor));
    }

    /**
     * @dev Set the token descriptor contract used to create the ERC-721 metadata URI
     * @param _tokenDescriptor Address of the contract that creates the NFT token URI
     */
    function _setTokenDescriptor(address _tokenDescriptor) internal {
        require(
            _tokenDescriptor != address(0) && AddressUpgradeable.isContract(_tokenDescriptor),
            "NFT: Invalid token descriptor"
        );
        tokenDescriptor = ISubgraphNFTDescriptor(_tokenDescriptor);
        emit TokenDescriptorUpdated(_tokenDescriptor);
    }
}
