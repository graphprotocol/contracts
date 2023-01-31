// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import { GNS } from "../../discovery/GNS.sol";
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

    /// @dev Emitted when a subgraph is received from L1 through the bridge
    event SubgraphReceivedFromL1(uint256 indexed _subgraphID);
    /// @dev Emitted when a subgraph migration from L1 is finalized, so the subgraph is published
    event SubgraphMigrationFinalized(uint256 indexed _subgraphID);
    /// @dev Emitted when the L1 balance for a curator has been claimed
    event CuratorBalanceReceived(uint256 _subgraphID, address _l2Curator, uint256 _tokens);
    /// @dev Emitted when the L1 balance for a curator has been returned to the beneficiary.
    /// This can happen if the subgraph migration was not finished when the curator's tokens arrived.
    event CuratorBalanceReturnedToBeneficiary(
        uint256 _subgraphID,
        address _l2Curator,
        uint256 _tokens
    );

    /**
     * @dev Checks that the sender is the L2GraphTokenGateway as configured on the Controller.
     */
    modifier onlyL2Gateway() {
        require(msg.sender == address(graphTokenGateway()), "ONLY_GATEWAY");
        _;
    }

    /**
     * @notice Receive tokens with a callhook from the bridge.
     * The callhook will receive a subgraph or a curator's balance from L1. The _data parameter
     * must contain the ABI encoding of:
     * (uint8 code, uint256 subgraphId, address beneficiary)
     * Where `code` is one of the codes defined in IL2GNS.L1MessageCodes.
     * If the code is RECEIVE_SUBGRAPH_CODE, the beneficiary is the address of the
     * owner of the subgraph on L2.
     * If the code is RECEIVE_CURATOR_BALANCE_CODE, then the beneficiary is the
     * address of the curator in L2. In this case, If the subgraph migration was never finished
     * (or the subgraph doesn't exist), the tokens will be sent to the curator.
     * @dev This function is called by the L2GraphTokenGateway contract.
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
        (uint8 code, uint256 subgraphID, address beneficiary) = abi.decode(
            _data,
            (uint8, uint256, address)
        );

        if (code == uint8(L1MessageCodes.RECEIVE_SUBGRAPH_CODE)) {
            _receiveSubgraphFromL1(subgraphID, beneficiary, _amount);
        } else if (code == uint8(L1MessageCodes.RECEIVE_CURATOR_BALANCE_CODE)) {
            _mintSignalFromL1(subgraphID, beneficiary, _amount);
        } else {
            revert("INVALID_CODE");
        }
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
        uint256 vSignal = curation.mintTaxFree(_subgraphDeploymentID, migratedData.tokens);
        uint256 nSignal = vSignalToNSignal(_subgraphID, vSignal);

        subgraphData.disabled = false;
        subgraphData.vSignal = vSignal;
        subgraphData.nSignal = nSignal;
        subgraphData.curatorNSignal[msg.sender] = nSignal;
        subgraphData.subgraphDeploymentID = _subgraphDeploymentID;
        // Set the token metadata
        _setSubgraphMetadata(_subgraphID, _subgraphMetadata);

        emit SubgraphPublished(_subgraphID, _subgraphDeploymentID, fixedReserveRatio);
        emit SubgraphUpgraded(
            _subgraphID,
            subgraphData.vSignal,
            migratedData.tokens,
            _subgraphDeploymentID
        );
        emit SubgraphVersionUpdated(_subgraphID, _subgraphDeploymentID, _versionMetadata);
        emit SubgraphMigrationFinalized(_subgraphID);
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
     */
    function _receiveSubgraphFromL1(
        uint256 _subgraphID,
        address _subgraphOwner,
        uint256 _tokens
    ) internal {
        IL2GNS.SubgraphL2MigrationData storage migratedData = subgraphL2MigrationData[_subgraphID];
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);

        subgraphData.reserveRatioDeprecated = fixedReserveRatio;
        // The subgraph will be disabled until finishSubgraphMigrationFromL1 is called
        subgraphData.disabled = true;

        migratedData.tokens = _tokens;
        migratedData.subgraphReceivedOnL2BlockNumber = block.number;

        // Mint the NFT. Use the subgraphID as tokenID.
        // This function will check the if tokenID already exists.
        _mintNFT(_subgraphOwner, _subgraphID);

        emit SubgraphReceivedFromL1(_subgraphID);
    }

    /**
     * @notice Deposit GRT into a subgraph and mint signal, using tokens received from L1.
     * If the subgraph migration was never finished (or the subgraph doesn't exist), the tokens will be sent to the curator.
     * @dev This looks a lot like GNS.mintSignal, but doesn't pull the tokens from the
     * curator and has no slippage protection.
     * @param _subgraphID Subgraph ID
     * @param _curator Curator address
     * @param _tokensIn The amount of tokens the nameCurator wants to deposit
     */
    function _mintSignalFromL1(
        uint256 _subgraphID,
        address _curator,
        uint256 _tokensIn
    ) internal {
        IL2GNS.SubgraphL2MigrationData storage migratedData = subgraphL2MigrationData[_subgraphID];
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);

        // If subgraph migration wasn't finished, we should send the tokens to the curator
        if (!migratedData.l2Done || subgraphData.disabled) {
            graphToken().transfer(_curator, _tokensIn);
            emit CuratorBalanceReturnedToBeneficiary(_subgraphID, _curator, _tokensIn);
        } else {
            // Get name signal to mint for tokens deposited
            IL2Curation curation = IL2Curation(address(curation()));
            uint256 vSignal = curation.mintTaxFree(subgraphData.subgraphDeploymentID, _tokensIn);
            uint256 nSignal = vSignalToNSignal(_subgraphID, vSignal);

            // Update pools
            subgraphData.vSignal = subgraphData.vSignal.add(vSignal);
            subgraphData.nSignal = subgraphData.nSignal.add(nSignal);
            subgraphData.curatorNSignal[_curator] = subgraphData.curatorNSignal[_curator].add(
                nSignal
            );

            emit SignalMinted(_subgraphID, _curator, nSignal, vSignal, _tokensIn);
            emit CuratorBalanceReceived(_subgraphID, _curator, _tokensIn);
        }
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
