// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "../libraries/Base58Encoder.sol";
import "./ISubgraphNFTDescriptor.sol";

/// @title Describes subgraph NFT tokens via URI
contract SubgraphNFTDescriptor is ISubgraphNFTDescriptor {
    /// @inheritdoc ISubgraphNFTDescriptor
    function tokenURI(
        address /* _minter */,
        uint256 /* _tokenId */,
        string calldata _baseURI,
        bytes32 _subgraphMetadata
    ) external pure override returns (string memory) {
        bytes memory b58 = Base58Encoder.encode(abi.encodePacked(Base58Encoder.sha256MultiHash, _subgraphMetadata));
        if (bytes(_baseURI).length == 0) {
            return string(b58);
        }
        return string(abi.encodePacked(_baseURI, b58));
    }
}
