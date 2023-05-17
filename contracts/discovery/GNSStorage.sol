// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import "../governance/Managed.sol";

import "./erc1056/IEthereumDIDRegistry.sol";
import "./IGNS.sol";
import "./ISubgraphNFT.sol";

abstract contract GNSV1Storage is Managed {
    // -- State --

    // In parts per hundred
    uint32 public ownerTaxPercentage;

    // Bonding curve formula
    address public bondingCurve;

    // Stores what subgraph deployment a particular legacy subgraph targets
    // A subgraph is defined by (graphAccountID, subgraphNumber)
    // A subgraph can target one subgraph deployment (bytes32 hash)
    // (graphAccountID, subgraphNumber) => subgraphDeploymentID
    mapping(address => mapping(uint256 => bytes32)) internal legacySubgraphs;

    // Every time an account creates a subgraph it increases a per-account sequence ID
    // account => seqID
    mapping(address => uint256) public nextAccountSeqID;

    // Stores all the signal deposited on a legacy subgraph
    // (graphAccountID, subgraphNumber) => SubgraphData
    mapping(address => mapping(uint256 => IGNS.SubgraphData)) public legacySubgraphData;

    // [DEPRECATED] ERC-1056 contract reference
    // This contract is used for managing identities
    IEthereumDIDRegistry private __DEPRECATED_erc1056Registry;
}

abstract contract GNSV2Storage is GNSV1Storage {
    // Use it whenever a legacy (v1) subgraph NFT was claimed to maintain compatibility
    // Keep a reference from subgraphID => (graphAccount, subgraphNumber)
    mapping(uint256 => IGNS.LegacySubgraphKey) public legacySubgraphKeys;

    // Store data for all NFT-based (v2) subgraphs
    // subgraphID => SubgraphData
    mapping(uint256 => IGNS.SubgraphData) public subgraphs;

    // Contract that represents subgraph ownership through an NFT
    ISubgraphNFT public subgraphNFT;
}
