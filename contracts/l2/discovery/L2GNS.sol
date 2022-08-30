// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { AddressAliasHelper } from "../../arbitrum/AddressAliasHelper.sol";
import { GNS } from "../../discovery/GNS.sol";
import { IGNS } from "../../discovery/IGNS.sol";
import { ICuration } from "../../curation/ICuration.sol";

import { RLPReader } from "../../libraries/RLPReader.sol";
import { StateProofVerifier as Verifier } from "../../libraries/StateProofVerifier.sol";

/**
 * @title GNS
 * @dev The Graph Name System contract provides a decentralized naming system for subgraphs
 * used in the scope of the Graph Network. It translates Subgraphs into Subgraph Versions.
 * Each version is associated with a Subgraph Deployment. The contract has no knowledge of
 * human-readable names. All human readable names emitted in events.
 * The contract implements a multicall behaviour to support batching multiple calls in a single
 * transaction.
 */
contract L2GNS is GNS {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;
    using SafeMath for uint256;

    // Storage slot where the subgraphs mapping is stored on L1GNS
    uint256 internal constant SUBGRAPH_MAPPING_SLOT = 18;
    // Storage slot where the legacy subgraphs mapping is stored on L1GNS
    uint256 internal constant LEGACY_SUBGRAPH_MAPPING_SLOT = 15;

    event SubgraphReceivedFromL1(uint256 _subgraphID);
    event SubgraphMigrationFinalized(uint256 _subgraphID);
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
        require(msg.sender == _resolveContract(keccak256("GraphTokenGateway")), "ONLY_GATEWAY");
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

    function receiveSubgraphFromL1(
        uint256 subgraphID,
        address subgraphOwner,
        uint256 tokens,
        bytes32 lockedAtBlockHash,
        uint256 nSignal,
        uint32 reserveRatio,
        bytes32 subgraphMetadata
    ) external notPartialPaused onlyL2Gateway {
        IGNS.SubgraphL2MigrationData storage migratedData = subgraphL2MigrationData[subgraphID];
        SubgraphData storage subgraphData = _getSubgraphData(subgraphID);

        subgraphData.reserveRatio = reserveRatio;
        // The subgraph will be disabled until finishSubgraphMigrationFromL1 is called
        subgraphData.disabled = true;
        subgraphData.nSignal = nSignal;

        migratedData.tokens = tokens;
        migratedData.lockedAtBlockHash = lockedAtBlockHash;
        migratedData.l1Done = true;

        // Mint the NFT. Use the subgraphID as tokenID.
        // This function will check the if tokenID already exists.
        _mintNFT(subgraphOwner, subgraphID);

        // Set the token metadata
        _setSubgraphMetadata(subgraphID, subgraphMetadata);
        emit SubgraphReceivedFromL1(subgraphID);
    }

    function finishSubgraphMigrationFromL1(
        uint256 _subgraphID,
        bytes32 _subgraphDeploymentID,
        bytes32 _versionMetadata
    ) external notPartialPaused onlySubgraphAuth(_subgraphID) {
        IGNS.SubgraphL2MigrationData storage migratedData = subgraphL2MigrationData[_subgraphID];
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        // A subgraph
        require(migratedData.l1Done, "INVALID_SUBGRAPH");
        require(!migratedData.l2Done, "ALREADY_DONE");
        migratedData.l2Done = true;

        // New subgraph deployment must be non-empty
        require(_subgraphDeploymentID != 0, "GNS: Cannot set deploymentID to 0");

        // This is to prevent the owner from front running its name curators signal by posting
        // its own signal ahead, bringing the name curators in, and dumping on them
        ICuration curation = curation();
        require(
            !curation.isCurated(_subgraphDeploymentID),
            "GNS: Owner cannot point to a subgraphID that has been pre-curated"
        );

        // Update pool: constant nSignal, vSignal can change (w/no slippage protection)
        // Buy all signal from the new deployment
        subgraphData.vSignal = curation.mintTaxFree(_subgraphDeploymentID, migratedData.tokens, 0);

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
    ) external notPartialPaused {
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

        uint256 curatorSlot = _getCuratorSlot(msg.sender, _subgraphID);

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
    ) external {
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

        uint256 curatorSlot = _getLegacyCuratorSlot(msg.sender, _subgraphCreatorAccount, _seqID);

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
    ) external notPartialPaused onlyL1Counterpart {
        GNS.SubgraphL2MigrationData storage migratedData = subgraphL2MigrationData[_subgraphID];

        require(migratedData.l2Done, "!MIGRATED");
        require(!migratedData.curatorBalanceClaimed[_curator], "ALREADY_CLAIMED");

        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        subgraphData.curatorNSignal[_beneficiary] = subgraphData.curatorNSignal[_beneficiary].add(
            _balance
        );
        migratedData.curatorBalanceClaimed[_curator] = true;
    }

    function _getCuratorSlot(address _curator, uint256 _subgraphID)
        internal
        pure
        returns (uint256)
    {
        // subgraphs mapping is stored at slot SUBGRAPH_MAPPING_SLOT.
        // So our subgraph is at slot keccak256(abi.encodePacked(uint256(subgraphID), uint256(SUBGRAPH_MAPPING_SLOT)))
        // The curatorNSignal mapping is at slot 2 within the SubgraphData struct,
        // So the mapping is at slot keccak256(abi.encodePacked(uint256(subgraphID), uint256(SUBGRAPH_MAPPING_SLOT))) + 2
        // Therefore the nSignal value for msg.sender should be at slot:
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        uint256(_curator),
                        uint256(keccak256(abi.encodePacked(_subgraphID, SUBGRAPH_MAPPING_SLOT)))
                            .add(2)
                    )
                )
            );
    }

    function _getLegacyCuratorSlot(
        address _curator,
        address _subgraphCreatorAccount,
        uint256 _seqID
    ) internal pure returns (uint256) {
        // legacy subgraphs mapping is stored at slot LEGACY_SUBGRAPH_MAPPING_SLOT.
        // So the subgraphs for the account are at slot keccak256(abi.encodePacked(uint256(_subgraphCreatorAccount), uint256(SUBGRAPH_MAPPING_SLOT)))
        uint256 accountSlot = uint256(
            keccak256(
                abi.encodePacked(uint256(_subgraphCreatorAccount), LEGACY_SUBGRAPH_MAPPING_SLOT)
            )
        );
        // Then the subgraph for this _seqID should be at:
        uint256 subgraphSlot = uint256(keccak256(abi.encodePacked(_seqID, accountSlot)));
        // The curatorNSignal mapping is at slot 2 within the SubgraphData struct,
        // So the mapping is at slot subgraphSlot + 2
        // Therefore the nSignal value for msg.sender should be at slot:
        return uint256(keccak256(abi.encodePacked(uint256(_curator), subgraphSlot.add(2))));
    }
}
