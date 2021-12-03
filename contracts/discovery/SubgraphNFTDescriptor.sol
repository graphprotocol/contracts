// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "./ISubgraphNFTDescriptor.sol";

/// @title Describes subgraph NFT tokens via URI
contract SubgraphNFTDescriptor is ISubgraphNFTDescriptor {
    /// @inheritdoc ISubgraphNFTDescriptor
    function tokenURI(
        address _minter,
        uint256 _tokenId,
        string calldata _baseURI,
        string calldata _subgraphURI
    ) external view override returns (string memory) {
        return string(abi.encodePacked(_baseURI, _subgraphURI));
    }
}
