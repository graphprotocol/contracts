// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../discovery/GNS.sol";
import "./L2GNSStorage.sol";

/**
 * @title GNS
 * @dev The Graph Name System contract provides a decentralized naming system for subgraphs
 * used in the scope of the Graph Network. It translates Subgraphs into Subgraph Versions.
 * Each version is associated with a Subgraph Deployment. The contract has no knowledge of
 * human-readable names. All human readable names emitted in events.
 * The contract implements a multicall behaviour to support batching multiple calls in a single
 * transaction.
 */
contract L2GNS is GNS, L2GNSV1Storage {
    event SubgraphReceivedFromL1(uint256 _subgraphID);
    event SubgraphMigrationFinalized(uint256 _subgraphID);

    /**
     * @dev Checks that the sender is the L2GraphTokenGateway as configured on the Controller.
     */
    modifier onlyL2Gateway() {
        require(msg.sender == _resolveContract(keccak256("GraphTokenGateway")), "ONLY_GATEWAY");
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
        IGNS.MigratedSubgraphData storage migratedData = migratedSubgraphData[subgraphID];
        SubgraphData storage subgraphData = subgraphs[subgraphID];

        subgraphData.reserveRatio = reserveRatio;
        // The subgraph will be disabled until finishSubgraphMigrationFromL1 is called
        subgraphData.disabled = true;
        subgraphData.nSignal = nSignal;

        migratedData.tokens = tokens;
        migratedData.lockedAtBlockHash = lockedAtBlockHash;

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
        IGNS.MigratedSubgraphData storage migratedData = migratedSubgraphData[_subgraphID];
        SubgraphData storage subgraphData = subgraphs[_subgraphID];
        // A subgraph
        require(migratedData.tokens > 0, "INVALID_SUBGRAPH");
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
     * @param _blockHeaderRlpBytes RLP-encoded block header from the block when the subgraph was locked on L1
     * @param _proofRlpBytes RLP-encoded list of proofs: first proof of the L1 GNS account, then proof of the slot for the curator's balance
     */
    function claimL1CuratorBalance(bytes memory _blockHeaderRlpBytes, bytes memory _proofRlpBytes)
        external
        notPartialPaused
    {
        // TODO
    }

    /**
     * @dev Claim curator balance belonging to a curator from L1.
     * This will be credited to the a beneficiary on L2, and a signature must be provided
     * to prove the L1 curator permits this assignment.
     * @param _blockHeaderRlpBytes RLP-encoded block header from the block when the subgraph was locked on L1
     * @param _proofRlpBytes RLP-encoded list of proofs: first proof of the L1 GNS account, then proof of the slot for the curator's balance
     * @param _beneficiary Address of a beneficiary for the balance
     * @param _deadline Expiration time of the signed permit
     * @param _v Signature version
     * @param _r Signature r value
     * @param _s Signature s value
     */
    function claimL1CuratorBalanceToBeneficiary(
        bytes memory _blockHeaderRlpBytes,
        bytes memory _proofRlpBytes,
        address _beneficiary,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external notPartialPaused {
        // TODO
    }
}
