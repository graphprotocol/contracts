// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { ICallhookReceiver } from "../../gateway/ICallhookReceiver.sol";

/**
 * @title Interface for the L2GNS contract.
 */
interface IL2GNS is ICallhookReceiver {
    /**
     * @dev The SubgraphL2MigrationData struct holds information
     * about a subgraph related to its migration from L1 to L2.
     */
    struct SubgraphL2MigrationData {
        uint256 tokens; // GRT that will be sent to L2 to mint signal
        mapping(address => bool) curatorBalanceClaimed; // True for curators whose balance has been claimed in L2
        bool l2Done; // Migration finished on L2 side
        uint256 subgraphReceivedOnL2BlockNumber; // Block number when the subgraph was received on L2
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
    ) external;

    /**
     * @notice Deprecate a subgraph that was migrated from L1, but for which
     * the migration was never finished. Anyone can call this function after a certain amount of
     * blocks have passed since the subgraph was migrated, if the subgraph owner didn't
     * call finishSubgraphMigrationFromL1. In L2GNS this timeout is the FINISH_MIGRATION_TIMEOUT constant.
     * @param _subgraphID Subgraph ID
     */
    function deprecateSubgraphMigratedFromL1(uint256 _subgraphID) external;

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
    ) external;
}
