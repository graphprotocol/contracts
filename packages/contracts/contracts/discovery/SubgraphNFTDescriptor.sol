// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { Base58Encoder } from "../libraries/Base58Encoder.sol";
import { ISubgraphNFTDescriptor } from "./ISubgraphNFTDescriptor.sol";

/**
 * @title Describes subgraph NFT tokens via URI
 * @author Edge & Node
 * @notice Describes subgraph NFT tokens via URI
 */
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
