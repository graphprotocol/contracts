// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;
pragma abicoder v2;

interface ISubgraphDisputeManager {
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
        address serviceProvider;
        address fisherman;
        uint256 deposit;
        bytes32 relatedDisputeID;
        DisputeType disputeType;
        DisputeStatus status;
        uint256 createdAt;
    }

    // -- Attestation --

    // Receipt content sent from the service provider in response to request
    struct Receipt {
        bytes32 requestCID;
        bytes32 responseCID;
        bytes32 subgraphDeploymentID;
    }

    // Attestation sent from the service provider in response to a request
    struct Attestation {
        bytes32 requestCID;
        bytes32 responseCID;
        bytes32 subgraphDeploymentID;
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    // -- Configuration --

    function setDisputePeriod(uint64 _disputePeriod) external;

    function setArbitrator(address _arbitrator) external;

    function setMinimumDeposit(uint256 _minimumDeposit) external;

    function setFishermanRewardPercentage(uint32 _percentage) external;

    function setMaxSlashingPercentage(uint32 _maxPercentage) external;

    // -- Getters --

    function getVerifierCut() external view returns (uint256);

    function getDisputePeriod() external view returns (uint64);

    function isDisputeCreated(bytes32 _disputeID) external view returns (bool);

    function encodeHashReceipt(Receipt memory _receipt) external view returns (bytes32);

    function areConflictingAttestations(
        Attestation memory _attestation1,
        Attestation memory _attestation2
    ) external pure returns (bool);

    function getAttestationServiceProvider(Attestation memory _attestation) external view returns (address);

    // -- Dispute --

    function createQueryDispute(bytes calldata _attestationData, uint256 _deposit) external returns (bytes32);

    function createQueryDisputeConflict(
        bytes calldata _attestationData1,
        bytes calldata _attestationData2
    ) external returns (bytes32, bytes32);

    function createIndexingDispute(address _allocationID, uint256 _deposit) external returns (bytes32);

    function acceptDispute(bytes32 _disputeID, uint256 _slashAmount) external;

    function rejectDispute(bytes32 _disputeID) external;

    function drawDispute(bytes32 _disputeID) external;

    function cancelDispute(bytes32 _disputeID) external;
}
