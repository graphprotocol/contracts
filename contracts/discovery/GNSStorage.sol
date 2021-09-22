// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "../governance/Managed.sol";

import "./erc1056/IEthereumDIDRegistry.sol";
import "./IGNS.sol";

contract GNSV1Storage is Managed {
    // -- State --

    // In parts per hundred
    uint32 public ownerTaxPercentage;

    // Bonding curve formula
    address public bondingCurve;

    // graphAccountID => subgraphNumber => subgraphDeploymentID
    // subgraphNumber = A number associated to a graph accounts deployed subgraph. This
    //                  is used to point to a subgraphID (graphAccountID + subgraphNumber)
    mapping(address => mapping(uint256 => bytes32)) public subgraphs;

    // graphAccountID => subgraph deployment counter
    mapping(address => uint256) public graphAccountSubgraphNumbers;

    // graphAccountID => subgraphNumber => NameCurationPool
    mapping(address => mapping(uint256 => IGNS.NameCurationPool)) public nameSignals;

    // ERC-1056 contract reference
    IEthereumDIDRegistry public erc1056Registry;
}
