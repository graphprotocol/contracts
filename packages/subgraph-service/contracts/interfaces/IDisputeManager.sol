// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;
pragma abicoder v2;

import { Attestation } from "../libraries/Attestation.sol";

interface IDisputeManager {
    // -- Dispute --

    enum DisputeType {
        Null,
        IndexingDispute,
        QueryDispute
    }

    enum DisputeStatus {
        Null,
        Accepted,
        Rejected,
        Drawn,
        Pending,
        Cancelled
    }

    // Disputes contain info necessary for the Arbitrator to verify and resolve
    struct Dispute {
        address indexer;
        address fisherman;
        uint256 deposit;
        bytes32 relatedDisputeId;
        DisputeType disputeType;
        DisputeStatus status;
        uint256 createdAt;
    }

    // -- Attestation --

    // -- Configuration --

    function setDisputePeriod(uint64 disputePeriod) external;

    function setArbitrator(address arbitrator) external;

    function setMinimumDeposit(uint256 minimumDeposit) external;

    function setFishermanRewardCut(uint32 cut) external;

    function setMaxSlashingCut(uint32 maxCut) external;

    // -- Dispute --

    function createQueryDispute(bytes calldata attestationData, uint256 deposit) external returns (bytes32);

    function createQueryDisputeConflict(
        bytes calldata attestationData1,
        bytes calldata attestationData2
    ) external returns (bytes32, bytes32);

    function createIndexingDispute(address allocationId, uint256 deposit) external returns (bytes32);

    function acceptDispute(bytes32 disputeId, uint256 tokensSlash) external;

    function rejectDispute(bytes32 disputeId) external;

    function drawDispute(bytes32 disputeId) external;

    function cancelDispute(bytes32 disputeId) external;

    // -- Getters --

    function getVerifierCut() external view returns (uint32);

    function getDisputePeriod() external view returns (uint64);

    function isDisputeCreated(bytes32 disputeId) external view returns (bool);

    function encodeReceipt(Attestation.Receipt memory receipt) external view returns (bytes32);

    function getAttestationIndexer(Attestation.State memory attestation) external view returns (address);

    function areConflictingAttestations(
        Attestation.State memory attestation1,
        Attestation.State memory attestation2
    ) external pure returns (bool);
}
