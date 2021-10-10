// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "./ISubgraphNFTDescriptor.sol";

/// @title Describes subgraph NFT tokens via URI
contract SubgraphNFTDescriptor is ISubgraphNFTDescriptor {
    /// @inheritdoc ISubgraphNFTDescriptor
    function tokenURI(IGNS _gns, uint256 _subgraphID)
        external
        view
        override
        returns (string memory)
    {
        // TODO: fancy implementation
        // uint256 signal = _gns.subgraphSignal(_subgraphID);
        // uint256 tokens = _gns.subgraphTokens(_subgraphID);
        // id
        // owner
        return "";
    }
}
