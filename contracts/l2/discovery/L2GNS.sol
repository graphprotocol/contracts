// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { AddressAliasHelper } from "../../arbitrum/AddressAliasHelper.sol";
import { GNS } from "../../discovery/GNS.sol";
import { IGNS } from "../../discovery/IGNS.sol";
import { ICuration } from "../../curation/ICuration.sol";
import { IL2GNS } from "./IL2GNS.sol";
import { L2GNSV1Storage } from "./L2GNSStorage.sol";

import { RLPReader } from "../../libraries/RLPReader.sol";
import { StateProofVerifier as Verifier } from "../../libraries/StateProofVerifier.sol";

import { IL2Curation } from "../curation/IL2Curation.sol";

/**
 * @title L2GNS
 * @dev The Graph Name System contract provides a decentralized naming system for subgraphs
 * used in the scope of the Graph Network. It translates Subgraphs into Subgraph Versions.
 * Each version is associated with a Subgraph Deployment. The contract has no knowledge of
 * human-readable names. All human readable names emitted in events.
 * The contract implements a multicall behaviour to support batching multiple calls in a single
 * transaction.
 */
contract L2GNS is GNS, L2GNSV1Storage, IL2GNS {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;
    using SafeMath for uint256;

    /// Emitted when a subgraph is received from L1 through the bridge
    event SubgraphReceivedFromL1(uint256 _subgraphID);
    event SubgraphMigrationFinalized(uint256 _subgraphID);
    event CuratorBalanceClaimed(
        uint256 _subgraphID,
        address _l1Curator,
        address _l2Curator,
        uint256 _nSignalClaimed
    );
    event MPTClaimingEnabled();
    event MPTClaimingDisabled();

    /**
     * @dev Checks that the sender is the L2GraphTokenGateway as configured on the Controller.
     */
    modifier onlyL2Gateway() {
        require(msg.sender == _resolveContract(keccak256("GraphTokenGateway")), "ONLY_GATEWAY");
        _;
    }

    /**
     * @dev Checks that claiming balances using Merkle Patricia proofs is enabled.
     */
    modifier ifMPTClaimingEnabled() {
        require(mptClaimingEnabled, "MPT_CLAIMING_DISABLED");
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
     * @notice Enables or disables claiming L1 balances using Merkle Patricia proofs
     * @param _enabled If true, claiming MPT proofs will be enabled; if false, they will be disabled
     */
    function setMPTClaimingEnabled(bool _enabled) external onlyGovernor {
        mptClaimingEnabled = _enabled;
        if (_enabled) {
            emit MPTClaimingEnabled();
        } else {
            emit MPTClaimingDisabled();
        }
    }

    /**
     * @dev Receive tokens with a callhook from the bridge.
     * The callhook will receive a subgraph from L1
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
        (
            uint256 subgraphID,
            address subgraphOwner,
            bytes32 lockedAtBlockHash,
            uint256 nSignal,
            uint32 reserveRatio
        ) = abi.decode(_data, (uint256, address, bytes32, uint256, uint32));

        _receiveSubgraphFromL1(
            subgraphID,
            subgraphOwner,
            _amount,
            lockedAtBlockHash,
            nSignal,
            reserveRatio
        );
    }

    function finishSubgraphMigrationFromL1(
        uint256 _subgraphID,
        bytes32 _subgraphDeploymentID,
        bytes32 _subgraphMetadata,
        bytes32 _versionMetadata
    ) external override notPartialPaused onlySubgraphAuth(_subgraphID) {
        IGNS.SubgraphL2MigrationData storage migratedData = subgraphL2MigrationData[_subgraphID];
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        // A subgraph
        require(migratedData.l1Done, "INVALID_SUBGRAPH");
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

        emit SubgraphPublished(_subgraphID, _subgraphDeploymentID, subgraphData.reserveRatio);
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
     * @dev Claim curator balance belonging to a curator from L1.
     * This will be credited to the same curator's balance on L2.
     * This can only be called by the corresponding curator.
     * @param _subgraphID Subgraph for which to claim a balance
     * @param _blockHeaderRlpBytes RLP-encoded block header from the block when the subgraph was locked on L1
     * @param _proofRlpBytes RLP-encoded list of proofs: first proof of the L1 GNS account, then proof of the slot for the curator's balance
     */
    function claimL1CuratorBalance(
        uint256 _subgraphID,
        bytes memory _blockHeaderRlpBytes,
        bytes memory _proofRlpBytes
    ) external override notPartialPaused ifMPTClaimingEnabled {
        IGNS.SubgraphL2MigrationData storage migratedData = subgraphL2MigrationData[_subgraphID];
        require(migratedData.l2Done, "!MIGRATED");
        require(!migratedData.curatorBalanceClaimed[msg.sender], "ALREADY_CLAIMED");

        Verifier.BlockHeader memory blockHeader = Verifier.parseBlockHeader(_blockHeaderRlpBytes);
        require(blockHeader.hash == migratedData.lockedAtBlockHash, "!BLOCKHASH");

        RLPReader.RLPItem[] memory proofs = _proofRlpBytes.toRlpItem().toList();
        require(proofs.length == 2, "!N_PROOFS");

        Verifier.Account memory l1GNSAccount = Verifier.extractAccountFromProof(
            keccak256(abi.encodePacked(counterpartGNSAddress)),
            blockHeader.stateRootHash,
            proofs[0].toList()
        );

        require(l1GNSAccount.exists, "!ACCOUNT");

        uint256 curatorSlot = getCuratorSlot(_subgraphID, msg.sender);

        Verifier.SlotValue memory curatorNSignalSlot = Verifier.extractSlotValueFromProof(
            keccak256(abi.encodePacked(curatorSlot)),
            l1GNSAccount.storageRoot,
            proofs[1].toList()
        );

        require(curatorNSignalSlot.exists, "!CURATOR_SLOT");

        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        subgraphData.curatorNSignal[msg.sender] = subgraphData.curatorNSignal[msg.sender].add(
            curatorNSignalSlot.value
        );
        migratedData.curatorBalanceClaimed[msg.sender] = true;

        emit CuratorBalanceClaimed(_subgraphID, msg.sender, msg.sender, curatorNSignalSlot.value);
    }

    /**
     * @dev Claim curator balance belonging to a curator from L1 on a legacy subgraph.
     * This will be credited to the same curator's balance on L2.
     * This can only be called by the corresponding curator.
     * Users can query getLegacySubgraphKey on L1 to get the _subgraphCreatorAccount and _seqID.
     * @param _subgraphCreatorAccount Account that created the subgraph in L1
     * @param _seqID Sequence number for the subgraph
     * @param _blockHeaderRlpBytes RLP-encoded block header from the block when the subgraph was locked on L1
     * @param _proofRlpBytes RLP-encoded list of proofs: first proof of the L1 GNS account, then proof of the slot for the curator's balance
     */
    function claimL1CuratorBalanceForLegacySubgraph(
        address _subgraphCreatorAccount,
        uint256 _seqID,
        bytes memory _blockHeaderRlpBytes,
        bytes memory _proofRlpBytes
    ) external override notPartialPaused ifMPTClaimingEnabled {
        uint256 _subgraphID = _buildLegacySubgraphID(_subgraphCreatorAccount, _seqID);

        Verifier.BlockHeader memory blockHeader = Verifier.parseBlockHeader(_blockHeaderRlpBytes);
        IGNS.SubgraphL2MigrationData storage migratedData = subgraphL2MigrationData[_subgraphID];

        require(migratedData.l2Done, "!MIGRATED");
        require(blockHeader.hash == migratedData.lockedAtBlockHash, "!BLOCKHASH");
        require(!migratedData.curatorBalanceClaimed[msg.sender], "ALREADY_CLAIMED");

        RLPReader.RLPItem[] memory proofs = _proofRlpBytes.toRlpItem().toList();
        require(proofs.length == 2, "!N_PROOFS");

        Verifier.Account memory l1GNSAccount = Verifier.extractAccountFromProof(
            keccak256(abi.encodePacked(counterpartGNSAddress)),
            blockHeader.stateRootHash,
            proofs[0].toList()
        );

        require(l1GNSAccount.exists, "!ACCOUNT");

        uint256 curatorSlot = getLegacyCuratorSlot(_subgraphCreatorAccount, _seqID, msg.sender);

        Verifier.SlotValue memory curatorNSignalSlot = Verifier.extractSlotValueFromProof(
            keccak256(abi.encodePacked(curatorSlot)),
            l1GNSAccount.storageRoot,
            proofs[1].toList()
        );

        require(curatorNSignalSlot.exists, "!CURATOR_SLOT");

        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        subgraphData.curatorNSignal[msg.sender] = subgraphData.curatorNSignal[msg.sender].add(
            curatorNSignalSlot.value
        );
        migratedData.curatorBalanceClaimed[msg.sender] = true;

        emit CuratorBalanceClaimed(_subgraphID, msg.sender, msg.sender, curatorNSignalSlot.value);
    }

    /**
     * @dev Claim curator balance belonging to a curator from L1.
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
        GNS.SubgraphL2MigrationData storage migratedData = subgraphL2MigrationData[_subgraphID];

        require(migratedData.l2Done, "!MIGRATED");
        require(!migratedData.curatorBalanceClaimed[_curator], "ALREADY_CLAIMED");

        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        subgraphData.curatorNSignal[_beneficiary] = subgraphData.curatorNSignal[_beneficiary].add(
            _balance
        );
        migratedData.curatorBalanceClaimed[_curator] = true;
        emit CuratorBalanceClaimed(_subgraphID, _curator, _beneficiary, _balance);
    }

    // TODO add NatSpec
    function _receiveSubgraphFromL1(
        uint256 _subgraphID,
        address _subgraphOwner,
        uint256 _tokens,
        bytes32 _lockedAtBlockHash,
        uint256 _nSignal,
        uint32 _reserveRatio
    ) internal {
        IGNS.SubgraphL2MigrationData storage migratedData = subgraphL2MigrationData[_subgraphID];
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);

        subgraphData.reserveRatio = _reserveRatio;
        // The subgraph will be disabled until finishSubgraphMigrationFromL1 is called
        subgraphData.disabled = true;
        subgraphData.nSignal = _nSignal;

        migratedData.tokens = _tokens;
        migratedData.lockedAtBlockHash = _lockedAtBlockHash;
        migratedData.l1Done = true;

        // Mint the NFT. Use the subgraphID as tokenID.
        // This function will check the if tokenID already exists.
        _mintNFT(_subgraphOwner, _subgraphID);

        emit SubgraphReceivedFromL1(_subgraphID);
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
        if (subgraphData.nSignal > 0) {
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
