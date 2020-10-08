pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../governance/Managed.sol";

import "./erc1056/IEthereumDIDRegistry.sol";

import "./IGNS.sol";

contract GNSV1Storage is Managed {
    // -- State --

    // In parts per hundred
    uint32 public ownerFeePercentage;

    // Bonding curve formula
    address public bondingCurve;

    // Minimum amount of vSignal that must be staked to start the curve
    // Set to 10**18, as vSignal has 18 decimals
    uint256 public minimumVSignalStake;

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
