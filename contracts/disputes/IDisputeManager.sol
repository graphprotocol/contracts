// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

interface IDisputeManager {
    // -- Dispute --

    // Disputes contain info necessary for the Arbitrator to verify and resolve
    struct Dispute {
        address indexer;
        address fisherman;
        uint256 deposit;
        bytes32 relatedDisputeID;
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

    function setArbitrator(address _arbitrator) external;

    function setMinimumDeposit(uint256 _minimumDeposit) external;

    function setFishermanRewardPercentage(uint32 _percentage) external;

    function setSlashingPercentage(uint32 _percentage) external;

    // -- Getters --

    function isDisputeCreated(bytes32 _disputeID) external view returns (bool);

    function encodeHashReceipt(Receipt memory _receipt) external view returns (bytes32);

    function areConflictingAttestations(
        Attestation memory _attestation1,
        Attestation memory _attestation2
    ) external pure returns (bool);

    function getAttestationIndexer(Attestation memory _attestation) external view returns (address);

    function getTokensToReward(address _indexer) external view returns (uint256);

    function getTokensToSlash(address _indexer) external view returns (uint256);

    // -- Dispute --

    function createQueryDispute(bytes calldata _attestationData, uint256 _deposit)
        external
        returns (bytes32);

    function createQueryDisputeConflict(
        bytes calldata _attestationData1,
        bytes calldata _attestationData2
    ) external returns (bytes32, bytes32);

    function createIndexingDispute(address _allocationID, uint256 _deposit)
        external
        returns (bytes32);

    function acceptDispute(bytes32 _disputeID) external;

    function rejectDispute(bytes32 _disputeID) external;

    function drawDispute(bytes32 _disputeID) external;
}
