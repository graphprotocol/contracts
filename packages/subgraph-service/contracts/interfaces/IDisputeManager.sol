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

    function setDisputePeriod(uint64 _disputePeriod) external;

    function setArbitrator(address _arbitrator) external;

    function setMinimumDeposit(uint256 _minimumDeposit) external;

    function setFishermanRewardPercentage(uint32 _percentage) external;

    function setMaxSlashingPercentage(uint32 _maxPercentage) external;

    // -- Getters --

    function getVerifierCut() external view returns (uint32);

    function getDisputePeriod() external view returns (uint64);

    function isDisputeCreated(bytes32 _disputeId) external view returns (bool);

    function encodeReceipt(Attestation.Receipt memory _receipt) external view returns (bytes32);

    function areConflictingAttestations(
        Attestation.State memory _attestation1,
        Attestation.State memory _attestation2
    ) external pure returns (bool);

    function getAttestationIndexer(Attestation.State memory _attestation) external view returns (address);

    // -- Dispute --

    function createQueryDispute(bytes calldata _attestationData, uint256 _deposit) external returns (bytes32);

    function createQueryDisputeConflict(
        bytes calldata _attestationData1,
        bytes calldata _attestationData2
    ) external returns (bytes32, bytes32);

    function createIndexingDispute(address _allocationId, uint256 _deposit) external returns (bytes32);

    function acceptDispute(bytes32 _disputeId, uint256 _slashAmount) external;

    function rejectDispute(bytes32 _disputeId) external;

    function drawDispute(bytes32 _disputeId) external;

    function cancelDispute(bytes32 _disputeId) external;
}
