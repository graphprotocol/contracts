// SPDX-License-Identifier: GPL-2.0-or-later
// solhint-disable one-contract-per-file

pragma solidity ^0.7.6;
pragma abicoder v2;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable named-parameters-mapping

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import { Managed } from "../governance/Managed.sol";

import { IEthereumDIDRegistry } from "@graphprotocol/interfaces/contracts/contracts/discovery/erc1056/IEthereumDIDRegistry.sol";
import { IGNS } from "@graphprotocol/interfaces/contracts/contracts/discovery/IGNS.sol";
import { ISubgraphNFT } from "@graphprotocol/interfaces/contracts/contracts/discovery/ISubgraphNFT.sol";

/**
 * @title GNSV1Storage
 * @author Edge & Node
 * @notice This contract holds all the storage variables for the GNS contract, version 1
 */
abstract contract GNSV1Storage is Managed {
    // -- State --

    /// @notice Percentage of curation tax that must be paid by the owner, in parts per million.
    uint32 public ownerTaxPercentage;

    /// @dev [DEPRECATED] Bonding curve formula.
    address private __DEPRECATED_bondingCurve; // solhint-disable-line var-name-mixedcase

    /// @dev Stores what subgraph deployment a particular legacy subgraph targets.
    /// A subgraph is defined by (graphAccountID, subgraphNumber).
    /// A subgraph can target one subgraph deployment (bytes32 hash).
    /// (graphAccountID, subgraphNumber) => subgraphDeploymentID
    mapping(address => mapping(uint256 => bytes32)) internal legacySubgraphs;

    /// @notice Every time an account creates a subgraph it increases a per-account sequence ID.
    /// account => seqID
    mapping(address => uint256) public nextAccountSeqID;

    /// @notice Stores all the signal deposited on a legacy subgraph.
    /// (graphAccountID, subgraphNumber) => SubgraphData
    mapping(address => mapping(uint256 => IGNS.SubgraphData)) public legacySubgraphData;

    /// @dev [DEPRECATED] ERC-1056 contract reference.
    ///  This contract was used for managing identities.
    IEthereumDIDRegistry private __DEPRECATED_erc1056Registry; // solhint-disable-line var-name-mixedcase
}

/**
 * @title GNSV2Storage
 * @author Edge & Node
 * @notice This contract holds all the storage variables for the GNS contract, version 2
 */
abstract contract GNSV2Storage is GNSV1Storage {
    /// @notice Stores the account and seqID for a legacy subgraph that has been migrated.
    /// Use it whenever a legacy (v1) subgraph NFT was claimed to maintain compatibility.
    /// Keep a reference from subgraphID => (graphAccount, subgraphNumber)
    mapping(uint256 => IGNS.LegacySubgraphKey) public legacySubgraphKeys;

    /// @notice Store data for all NFT-based (v2) subgraphs.
    /// subgraphID => SubgraphData
    mapping(uint256 => IGNS.SubgraphData) public subgraphs;

    /// @notice Contract that represents subgraph ownership through an NFT
    ISubgraphNFT public subgraphNFT;
}

/**
 * @title GNSV3Storage
 * @author Edge & Node
 * @notice This contract holds all the storage variables for the base GNS contract, version 3.
 * @dev Note that this is the first version that includes a storage gap - if adding
 * future versions, make sure to move the gap to the new version and
 * reduce the size of the gap accordingly.
 */
abstract contract GNSV3Storage is GNSV2Storage, Initializable {
    /// @notice Address of the counterpart GNS contract (L1GNS/L2GNS)
    address public counterpartGNSAddress;
    /// @dev Gap to allow adding variables in future upgrades (since L1GNS and L2GNS have their own storage as well)
    uint256[50] private __gap;
}
