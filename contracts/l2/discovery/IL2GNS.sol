// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { ICallhookReceiver } from "../../gateway/ICallhookReceiver.sol";

interface IL2GNS is ICallhookReceiver {
    function finishSubgraphMigrationFromL1(
        uint256 _subgraphID,
        bytes32 _subgraphDeploymentID,
        bytes32 _subgraphMetadata,
        bytes32 _versionMetadata
    ) external;

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
    ) external;

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
    ) external;

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
    ) external;
}
