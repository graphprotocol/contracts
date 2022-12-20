// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import { AddressAliasHelper } from "../../arbitrum/AddressAliasHelper.sol";
import { GNS } from "../../discovery/GNS.sol";
import { IGNS } from "../../discovery/IGNS.sol";
import { ICuration } from "../../curation/ICuration.sol";
import { IL2GNS } from "./IL2GNS.sol";
import { L2GNSV1Storage } from "./L2GNSStorage.sol";

import { IL2Curation } from "../curation/IL2Curation.sol";

/**
 * @title L2GNS
 * @dev The Graph Name System contract provides a decentralized naming system for subgraphs
 * used in the scope of the Graph Network. It translates Subgraphs into Subgraph Versions.
 * Each version is associated with a Subgraph Deployment. The contract has no knowledge of
 * human-readable names. All human readable names emitted in events.
 * The contract implements a multicall behaviour to support batching multiple calls in a single
 * transaction.
 * This particular contract is meant to be deployed in L2, and includes helper functions to
 * receive subgraphs that are migrated from L1.
 */
contract L2GNS is GNS, L2GNSV1Storage, IL2GNS {
    using SafeMathUpgradeable for uint256;

    /// The amount of time (in blocks) that a subgraph owner has to finish the migration
    /// from L1 before the subgraph can be deprecated: 1 week
    uint256 public constant FINISH_MIGRATION_TIMEOUT = 50400;

    /// @dev Emitted when a subgraph is received from L1 through the bridge
    event SubgraphReceivedFromL1(uint256 _subgraphID);
    /// @dev Emitted when a subgraph migration from L1 is finalized, so the subgraph is published
    event SubgraphMigrationFinalized(uint256 _subgraphID);
    /// @dev Emitted when the L1 balance for a curator has been claimed
    event CuratorBalanceClaimed(
        uint256 _subgraphID,
        address _l1Curator,
        address _l2Curator,
        uint256 _nSignalClaimed
    );

    /**
     * @dev Checks that the sender is the L2GraphTokenGateway as configured on the Controller.
     */
    modifier onlyL2Gateway() {
        require(msg.sender == address(graphTokenGateway()), "ONLY_GATEWAY");
        _;
    }

    /**
     * @dev Checks that the sender is the L2 alias of the counterpart
     * GNS on L1.
     */
    modifier onlyL1Counterpart() {
        require(
            msg.sender == AddressAliasHelper.applyL1ToL2Alias(counterpartGNSAddress),
            "ONLY_COUNTERPART_GNS"
        );
        _;
    }

    /**
     * @notice Receive tokens with a callhook from the bridge.
     * The callhook will receive a subgraph from L1.
     * @param _from Token sender in L1 (must be the L1GNS)
     * @param _amount Amount of tokens that were transferred
     * @param _data ABI-encoded callhook data
     */
    function onTokenTransfer(
        address _from,
        uint256 _amount,
        bytes calldata _data
    ) external override notPartialPaused onlyL2Gateway {
        require(_from == counterpartGNSAddress, "ONLY_L1_GNS_THROUGH_BRIDGE");
        (uint256 subgraphID, address subgraphOwner, uint256 nSignal) = abi.decode(
            _data,
            (uint256, address, uint256)
        );

        _receiveSubgraphFromL1(subgraphID, subgraphOwner, _amount, nSignal);
    }

    /**
     * @notice Finish a subgraph migration from L1.
     * The subgraph must have been previously sent through the bridge
     * using the sendSubgraphToL2 function on L1GNS.
     * @param _subgraphID Subgraph ID
     * @param _subgraphDeploymentID Latest subgraph deployment to assign to the subgraph
     * @param _subgraphMetadata IPFS hash of the subgraph metadata
     * @param _versionMetadata IPFS hash of the version metadata
     */
    function finishSubgraphMigrationFromL1(
        uint256 _subgraphID,
        bytes32 _subgraphDeploymentID,
        bytes32 _subgraphMetadata,
        bytes32 _versionMetadata
    ) external override notPartialPaused onlySubgraphAuth(_subgraphID) {
        IL2GNS.SubgraphL2MigrationData storage migratedData = subgraphL2MigrationData[_subgraphID];
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        // A subgraph
        require(migratedData.subgraphReceivedOnL2BlockNumber != 0, "INVALID_SUBGRAPH");
        require(!migratedData.l2Done, "ALREADY_DONE");
        migratedData.l2Done = true;

        // New subgraph deployment must be non-empty
        require(_subgraphDeploymentID != 0, "GNS: deploymentID != 0");

        IL2Curation curation = IL2Curation(address(curation()));
        // Update pool: constant nSignal, vSignal can change (w/no slippage protection)
        // Buy all signal from the new deployment
        subgraphData.vSignal = curation.mintTaxFree(_subgraphDeploymentID, migratedData.tokens, 0);
        subgraphData.disabled = false;

        // Set the token metadata
        _setSubgraphMetadata(_subgraphID, _subgraphMetadata);

        emit SubgraphPublished(_subgraphID, _subgraphDeploymentID, fixedReserveRatio);
        emit SubgraphUpgraded(
            _subgraphID,
            subgraphData.vSignal,
            migratedData.tokens,
            _subgraphDeploymentID
        );
        // Update target deployment
        subgraphData.subgraphDeploymentID = _subgraphDeploymentID;
        emit SubgraphVersionUpdated(_subgraphID, _subgraphDeploymentID, _versionMetadata);
        emit SubgraphMigrationFinalized(_subgraphID);
    }

    /**
     * @notice Deprecate a subgraph that was migrated from L1, but for which
     * the migration was never finished. Anyone can call this function after a certain amount of
     * blocks have passed since the subgraph was migrated, if the subgraph owner didn't
     * call finishSubgraphMigrationFromL1. In L2GNS this timeout is the FINISH_MIGRATION_TIMEOUT constant.
     * @param _subgraphID Subgraph ID
     */
    function deprecateSubgraphMigratedFromL1(uint256 _subgraphID)
        external
        override
        notPartialPaused
    {
        IL2GNS.SubgraphL2MigrationData storage migratedData = subgraphL2MigrationData[_subgraphID];
        require(migratedData.subgraphReceivedOnL2BlockNumber != 0, "INVALID_SUBGRAPH");
        require(!migratedData.l2Done, "ALREADY_FINISHED");
        require(
            block.number > migratedData.subgraphReceivedOnL2BlockNumber + FINISH_MIGRATION_TIMEOUT,
            "TOO_EARLY"
        );
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);

        migratedData.l2Done = true;
        uint256 withdrawableGRT = migratedData.tokens;
        subgraphData.withdrawableGRT = withdrawableGRT;
        subgraphData.reserveRatioDeprecated = 0;
        _burnNFT(_subgraphID);
        emit SubgraphDeprecated(_subgraphID, withdrawableGRT);
    }

    /**
     * @notice Claim curator balance belonging to a curator from L1.
     * This will be credited to the a beneficiary on L2, and can only be called
     * from the GNS on L1 through a retryable ticket.
     * @param _subgraphID Subgraph on which to claim the balance
     * @param _curator Curator who owns the balance on L1
     * @param _balance Balance of the curator from L1
     * @param _beneficiary Address of an L2 beneficiary for the balance
     */
    function claimL1CuratorBalanceToBeneficiary(
        uint256 _subgraphID,
        address _curator,
        uint256 _balance,
        address _beneficiary
    ) external override notPartialPaused onlyL1Counterpart {
        IL2GNS.SubgraphL2MigrationData storage migratedData = subgraphL2MigrationData[_subgraphID];

        require(migratedData.l2Done, "!MIGRATED");
        require(!migratedData.curatorBalanceClaimed[_curator], "ALREADY_CLAIMED");

        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        subgraphData.curatorNSignal[_beneficiary] = subgraphData.curatorNSignal[_beneficiary].add(
            _balance
        );
        migratedData.curatorBalanceClaimed[_curator] = true;
        emit CuratorBalanceClaimed(_subgraphID, _curator, _beneficiary, _balance);
    }

    /**
     * @notice Publish a new version of an existing subgraph.
     * @dev This is the same as the one in the base GNS, but skips the check for
     * a subgraph to not be pre-curated, as the reserve ration in L2 is set to 1,
     * which prevents the risk of rug-pulling.
     * @param _subgraphID Subgraph ID
     * @param _subgraphDeploymentID Subgraph deployment ID of the new version
     * @param _versionMetadata IPFS hash for the subgraph version metadata
     */
    function publishNewVersion(
        uint256 _subgraphID,
        bytes32 _subgraphDeploymentID,
        bytes32 _versionMetadata
    ) external override notPaused onlySubgraphAuth(_subgraphID) {
        // Perform the upgrade from the current subgraph deployment to the new one.
        // This involves burning all signal from the old deployment and using the funds to buy
        // from the new deployment.
        // This will also make the change to target to the new deployment.

        // Subgraph check
        SubgraphData storage subgraphData = _getSubgraphOrRevert(_subgraphID);

        // New subgraph deployment must be non-empty
        require(_subgraphDeploymentID != 0, "GNS: Cannot set deploymentID to 0 in publish");

        // New subgraph deployment must be different than current
        require(
            _subgraphDeploymentID != subgraphData.subgraphDeploymentID,
            "GNS: Cannot publish a new version with the same subgraph deployment ID"
        );

        ICuration curation = curation();

        // Move all signal from previous version to new version
        // NOTE: We will only do this as long as there is signal on the subgraph
        if (subgraphData.nSignal != 0) {
            // Burn all version signal in the name pool for tokens (w/no slippage protection)
            // Sell all signal from the old deployment
            uint256 tokens = curation.burn(
                subgraphData.subgraphDeploymentID,
                subgraphData.vSignal,
                0
            );

            // Take the owner cut of the curation tax, add it to the total
            // Upgrade is only callable by the owner, we assume then that msg.sender = owner
            address subgraphOwner = msg.sender;
            uint256 tokensWithTax = _chargeOwnerTax(
                tokens,
                subgraphOwner,
                curation.curationTaxPercentage()
            );

            // Update pool: constant nSignal, vSignal can change (w/no slippage protection)
            // Buy all signal from the new deployment
            (subgraphData.vSignal, ) = curation.mint(_subgraphDeploymentID, tokensWithTax, 0);

            emit SubgraphUpgraded(
                _subgraphID,
                subgraphData.vSignal,
                tokensWithTax,
                _subgraphDeploymentID
            );
        }

        // Update target deployment
        subgraphData.subgraphDeploymentID = _subgraphDeploymentID;

        emit SubgraphVersionUpdated(_subgraphID, _subgraphDeploymentID, _versionMetadata);
    }

    /**
     * @dev Receive a subgraph from L1.
     * This function will initialize a subgraph received through the bridge,
     * and store the migration data so that it's finalized later using finishSubgraphMigrationFromL1.
     * @param _subgraphID Subgraph ID
     * @param _subgraphOwner Owner of the subgraph
     * @param _tokens Tokens to be deposited in the subgraph
     * @param _nSignal Name signal for the subgraph in L1
     */
    function _receiveSubgraphFromL1(
        uint256 _subgraphID,
        address _subgraphOwner,
        uint256 _tokens,
        uint256 _nSignal
    ) internal {
        IL2GNS.SubgraphL2MigrationData storage migratedData = subgraphL2MigrationData[_subgraphID];
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);

        subgraphData.reserveRatioDeprecated = fixedReserveRatio;
        // The subgraph will be disabled until finishSubgraphMigrationFromL1 is called
        subgraphData.disabled = true;
        subgraphData.nSignal = _nSignal;

        migratedData.tokens = _tokens;
        migratedData.subgraphReceivedOnL2BlockNumber = block.number;

        // Mint the NFT. Use the subgraphID as tokenID.
        // This function will check the if tokenID already exists.
        _mintNFT(_subgraphOwner, _subgraphID);

        emit SubgraphReceivedFromL1(_subgraphID);
    }

    /**
     * @dev Get subgraph data.
     * Since there are no legacy subgraphs in L2, we override the base
     * GNS method to save us the step of checking for legacy subgraphs.
     * @param _subgraphID Subgraph ID
     * @return Subgraph Data
     */
    function _getSubgraphData(uint256 _subgraphID)
        internal
        view
        override
        returns (SubgraphData storage)
    {
        // Return new subgraph type
        return subgraphs[_subgraphID];
    }
}
