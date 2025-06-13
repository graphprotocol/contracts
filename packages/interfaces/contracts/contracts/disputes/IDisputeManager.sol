// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.6.12 <0.8.0 || 0.8.27;
pragma abicoder v2;

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
        Pending
    }

    // Disputes contain info necessary for the Arbitrator to verify and resolve
    struct Dispute {
        address indexer;
        address fisherman;
        uint256 deposit;
        bytes32 relatedDisputeID;
        DisputeType disputeType;
        DisputeStatus status;
    }

    // -- Attestation --

    // Receipt content sent from indexer in response to request
    struct Receipt {
        bytes32 requestCID;
        bytes32 responseCID;
        bytes32 subgraphDeploymentID;
    }

    // Attestation sent from indexer in response to a request
    struct Attestation {
        bytes32 requestCID;
        bytes32 responseCID;
        bytes32 subgraphDeploymentID;
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    // -- Configuration --

    function setArbitrator(address arbitrator) external;

    function setMinimumDeposit(uint256 minimumDeposit) external;

    function setFishermanRewardPercentage(uint32 percentage) external;

    function setSlashingPercentage(uint32 qryPercentage, uint32 idxPercentage) external;

    // -- Getters --

    function isDisputeCreated(bytes32 disputeID) external view returns (bool);

    function encodeHashReceipt(Receipt memory receipt) external view returns (bytes32);

    function areConflictingAttestations(
        Attestation memory attestation1,
        Attestation memory attestation2
    ) external pure returns (bool);

    function getAttestationIndexer(Attestation memory attestation) external view returns (address);

    // -- Dispute --

    function createQueryDispute(bytes calldata attestationData, uint256 deposit) external returns (bytes32);

    function createQueryDisputeConflict(
        bytes calldata attestationData1,
        bytes calldata attestationData2
    ) external returns (bytes32, bytes32);

    function createIndexingDispute(address allocationID, uint256 deposit) external returns (bytes32);

    function acceptDispute(bytes32 disputeID) external;

    function rejectDispute(bytes32 disputeID) external;

    function drawDispute(bytes32 disputeID) external;
}
