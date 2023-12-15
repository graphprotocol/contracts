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
 * receive subgraphs that are transferred from L1.
 */
contract L2GNS is GNS, L2GNSV1Storage, IL2GNS {
    using SafeMathUpgradeable for uint256;

    /// Offset added to an L1 subgraph ID to compute the L2 subgraph ID alias
    uint256 public constant SUBGRAPH_ID_ALIAS_OFFSET =
        uint256(0x1111000000000000000000000000000000000000000000000000000000001111);

    /// Maximum rounding error when receiving signal tokens from L1, in parts-per-million.
    /// If the error from minting signal is above this, tokens will be sent back to the curator.
    uint256 public constant MAX_ROUNDING_ERROR = 1000;

    /// @dev 100% expressed in parts-per-million
    uint256 private constant MAX_PPM = 1000000;

    /// @dev Emitted when a subgraph is received from L1 through the bridge
    event SubgraphReceivedFromL1(
        uint256 indexed _l1SubgraphID,
        uint256 indexed _l2SubgraphID,
        address indexed _owner,
        uint256 _tokens
    );
    /// @dev Emitted when a subgraph transfer from L1 is finalized, so the subgraph is published on L2
    event SubgraphL2TransferFinalized(uint256 indexed _l2SubgraphID);
    /// @dev Emitted when the L1 balance for a curator has been claimed
    event CuratorBalanceReceived(
        uint256 indexed _l1SubgraphId,
        uint256 indexed _l2SubgraphID,
        address indexed _l2Curator,
        uint256 _tokens
    );
    /// @dev Emitted when the L1 balance for a curator has been returned to the beneficiary.
    /// This can happen if the subgraph transfer was not finished when the curator's tokens arrived.
    event CuratorBalanceReturnedToBeneficiary(
        uint256 indexed _l1SubgraphID,
        address indexed _l2Curator,
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
     * address of the curator in L2. In this case, If the subgraph transfer was never finished
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
        (uint8 code, uint256 l1SubgraphID, address beneficiary) = abi.decode(
            _data,
            (uint8, uint256, address)
        );

        if (code == uint8(L1MessageCodes.RECEIVE_SUBGRAPH_CODE)) {
            _receiveSubgraphFromL1(l1SubgraphID, beneficiary, _amount);
        } else if (code == uint8(L1MessageCodes.RECEIVE_CURATOR_BALANCE_CODE)) {
            _mintSignalFromL1(l1SubgraphID, beneficiary, _amount);
        } else {
            revert("INVALID_CODE");
        }
    }

    /**
     * @notice Finish a subgraph transfer from L1.
     * The subgraph must have been previously sent through the bridge
     * using the sendSubgraphToL2 function on L1GNS.
     * @param _l2SubgraphID Subgraph ID (aliased from the L1 subgraph ID)
     * @param _subgraphDeploymentID Latest subgraph deployment to assign to the subgraph
     * @param _subgraphMetadata IPFS hash of the subgraph metadata
     * @param _versionMetadata IPFS hash of the version metadata
     */
    function finishSubgraphTransferFromL1(
        uint256 _l2SubgraphID,
        bytes32 _subgraphDeploymentID,
        bytes32 _subgraphMetadata,
        bytes32 _versionMetadata
    ) external override notPartialPaused onlySubgraphAuth(_l2SubgraphID) {
        IL2GNS.SubgraphL2TransferData storage transferData = subgraphL2TransferData[_l2SubgraphID];
        SubgraphData storage subgraphData = _getSubgraphData(_l2SubgraphID);
        require(transferData.subgraphReceivedOnL2BlockNumber != 0, "INVALID_SUBGRAPH");
        require(!transferData.l2Done, "ALREADY_DONE");
        transferData.l2Done = true;

        // New subgraph deployment must be non-empty
        require(_subgraphDeploymentID != 0, "GNS: deploymentID != 0");

        IL2Curation curation = IL2Curation(address(curation()));

        uint256 vSignal;
        uint256 nSignal;
        uint256 roundingError;
        uint256 tokens = transferData.tokens;
        {
            // This can't revert because the bridge ensures that _tokensIn is > 0,
            // and the minimum curation in L2 is 1 wei GRT
            uint256 tokensAfter = curation.tokensToSignalToTokensNoTax(
                _subgraphDeploymentID,
                tokens
            );
            roundingError = tokens.sub(tokensAfter).mul(MAX_PPM).div(tokens);
        }
        if (roundingError <= MAX_ROUNDING_ERROR) {
            vSignal = curation.mintTaxFree(_subgraphDeploymentID, tokens);
            nSignal = vSignalToNSignal(_l2SubgraphID, vSignal);
            emit SignalMinted(_l2SubgraphID, msg.sender, nSignal, vSignal, tokens);
            emit SubgraphUpgraded(_l2SubgraphID, vSignal, tokens, _subgraphDeploymentID);
        } else {
            graphToken().transfer(msg.sender, tokens);
            emit CuratorBalanceReturnedToBeneficiary(
                getUnaliasedL1SubgraphID(_l2SubgraphID),
                msg.sender,
                tokens
            );
            emit SubgraphUpgraded(_l2SubgraphID, vSignal, 0, _subgraphDeploymentID);
        }

        subgraphData.disabled = false;
        subgraphData.vSignal = vSignal;
        subgraphData.nSignal = nSignal;
        subgraphData.curatorNSignal[msg.sender] = nSignal;
        subgraphData.subgraphDeploymentID = _subgraphDeploymentID;
        // Set the token metadata
        _setSubgraphMetadata(_l2SubgraphID, _subgraphMetadata);
        emit SubgraphPublished(_l2SubgraphID, _subgraphDeploymentID, fixedReserveRatio);
        emit SubgraphVersionUpdated(_l2SubgraphID, _subgraphDeploymentID, _versionMetadata);
        emit SubgraphL2TransferFinalized(_l2SubgraphID);
    }

    /**
     * @notice Publish a new version of an existing subgraph.
     * @dev This is the same as the one in the base GNS, but skips the check for
     * a subgraph to not be pre-curated, as the reserve ratio in L2 is set to 1,
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
     * @notice Return the aliased L2 subgraph ID from a transferred L1 subgraph ID
     * @param _l1SubgraphID L1 subgraph ID
     * @return L2 subgraph ID
     */
    function getAliasedL2SubgraphID(uint256 _l1SubgraphID) public pure override returns (uint256) {
        return _l1SubgraphID + SUBGRAPH_ID_ALIAS_OFFSET;
    }

    /**
     * @notice Return the unaliased L1 subgraph ID from a transferred L2 subgraph ID
     * @param _l2SubgraphID L2 subgraph ID
     * @return L1subgraph ID
     */
    function getUnaliasedL1SubgraphID(uint256 _l2SubgraphID)
        public
        pure
        override
        returns (uint256)
    {
        return _l2SubgraphID - SUBGRAPH_ID_ALIAS_OFFSET;
    }

    /**
     * @dev Receive a subgraph from L1.
     * This function will initialize a subgraph received through the bridge,
     * and store the transfer data so that it's finalized later using finishSubgraphTransferFromL1.
     * @param _l1SubgraphID Subgraph ID in L1 (will be aliased)
     * @param _subgraphOwner Owner of the subgraph
     * @param _tokens Tokens to be deposited in the subgraph
     */
    function _receiveSubgraphFromL1(
        uint256 _l1SubgraphID,
        address _subgraphOwner,
        uint256 _tokens
    ) internal {
        uint256 l2SubgraphID = getAliasedL2SubgraphID(_l1SubgraphID);
        SubgraphData storage subgraphData = _getSubgraphData(l2SubgraphID);
        IL2GNS.SubgraphL2TransferData storage transferData = subgraphL2TransferData[l2SubgraphID];

        subgraphData.__DEPRECATED_reserveRatio = fixedReserveRatio;
        // The subgraph will be disabled until finishSubgraphTransferFromL1 is called
        subgraphData.disabled = true;

        transferData.tokens = _tokens;
        transferData.subgraphReceivedOnL2BlockNumber = block.number;

        // Mint the NFT. Use the subgraphID as tokenID.
        // This function will check the if tokenID already exists.
        // Note we do this here so that we can later do the onlySubgraphAuth
        // check in finishSubgraphTransferFromL1.
        _mintNFT(_subgraphOwner, l2SubgraphID);

        emit SubgraphReceivedFromL1(_l1SubgraphID, l2SubgraphID, _subgraphOwner, _tokens);
    }

    /**
     * @notice Deposit GRT into a subgraph and mint signal, using tokens received from L1.
     * If the subgraph transfer was never finished (or the subgraph doesn't exist), the tokens will be sent to the curator.
     * @dev This looks a lot like GNS.mintSignal, but doesn't pull the tokens from the
     * curator and has no slippage protection.
     * @param _l1SubgraphID Subgraph ID in L1 (will be aliased)
     * @param _curator Curator address
     * @param _tokensIn The amount of tokens the nameCurator wants to deposit
     */
    function _mintSignalFromL1(
        uint256 _l1SubgraphID,
        address _curator,
        uint256 _tokensIn
    ) internal {
        uint256 l2SubgraphID = getAliasedL2SubgraphID(_l1SubgraphID);
        IL2GNS.SubgraphL2TransferData storage transferData = subgraphL2TransferData[l2SubgraphID];
        SubgraphData storage subgraphData = _getSubgraphData(l2SubgraphID);

        IL2Curation curation = IL2Curation(address(curation()));
        uint256 roundingError;
        if (transferData.l2Done && !subgraphData.disabled) {
            // This can't revert because the bridge ensures that _tokensIn is > 0,
            // and the minimum curation in L2 is 1 wei GRT
            uint256 tokensAfter = curation.tokensToSignalToTokensNoTax(
                subgraphData.subgraphDeploymentID,
                _tokensIn
            );
            roundingError = _tokensIn.sub(tokensAfter).mul(MAX_PPM).div(_tokensIn);
        }
        // If subgraph transfer wasn't finished, we should send the tokens to the curator
        if (!transferData.l2Done || subgraphData.disabled || roundingError > MAX_ROUNDING_ERROR) {
            graphToken().transfer(_curator, _tokensIn);
            emit CuratorBalanceReturnedToBeneficiary(_l1SubgraphID, _curator, _tokensIn);
        } else {
            // Get name signal to mint for tokens deposited
            uint256 vSignal = curation.mintTaxFree(subgraphData.subgraphDeploymentID, _tokensIn);
            uint256 nSignal = vSignalToNSignal(l2SubgraphID, vSignal);

            // Update pools
            subgraphData.vSignal = subgraphData.vSignal.add(vSignal);
            subgraphData.nSignal = subgraphData.nSignal.add(nSignal);
            subgraphData.curatorNSignal[_curator] = subgraphData.curatorNSignal[_curator].add(
                nSignal
            );

            emit SignalMinted(l2SubgraphID, _curator, nSignal, vSignal, _tokensIn);
            emit CuratorBalanceReceived(_l1SubgraphID, l2SubgraphID, _curator, _tokensIn);
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
