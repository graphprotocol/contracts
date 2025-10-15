// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.6.12 <0.8.0 || 0.8.27;
pragma abicoder v2;

/**
 * @title Dispute Manager Interface
 * @author Edge & Node
 * @notice Interface for the Dispute Manager contract that handles indexing and query disputes
 */
interface IDisputeManager {
    // -- Dispute --

    /**
     * @dev Types of disputes that can be created
     */
    enum DisputeType {
        Null,
        IndexingDispute,
        QueryDispute
    }

    /**
     * @dev Status of a dispute
     */
    enum DisputeStatus {
        Null,
        Accepted,
        Rejected,
        Drawn,
        Pending
    }

    /**
     * @dev Disputes contain info necessary for the Arbitrator to verify and resolve
     * @param indexer Address of the indexer being disputed
     * @param fisherman Address of the challenger creating the dispute
     * @param deposit Amount of tokens staked as deposit
     * @param relatedDisputeID ID of related dispute (for conflicting attestations)
     * @param disputeType Type of dispute (Query or Indexing)
     * @param status Current status of the dispute
     */
    struct Dispute {
        address indexer;
        address fisherman;
        uint256 deposit;
        bytes32 relatedDisputeID;
        DisputeType disputeType;
        DisputeStatus status;
    }

    // -- Attestation --

    /**
     * @dev Receipt content sent from indexer in response to request
     * @param requestCID Content ID of the request
     * @param responseCID Content ID of the response
     * @param subgraphDeploymentID ID of the subgraph deployment
     */
    struct Receipt {
        bytes32 requestCID;
        bytes32 responseCID;
        bytes32 subgraphDeploymentID;
    }

    /**
     * @dev Attestation sent from indexer in response to a request
     * @param requestCID Content ID of the request
     * @param responseCID Content ID of the response
     * @param subgraphDeploymentID ID of the subgraph deployment
     * @param r R component of the signature
     * @param s S component of the signature
     * @param v Recovery ID of the signature
     */
    struct Attestation {
        bytes32 requestCID;
        bytes32 responseCID;
        bytes32 subgraphDeploymentID;
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    // -- Configuration --

    /**
     * @dev Set the arbitrator address.
     * @notice Update the arbitrator to `arbitrator`
     * @param arbitrator The address of the arbitration contract or party
     */
    function setArbitrator(address arbitrator) external;

    /**
     * @dev Set the minimum deposit required to create a dispute.
     * @notice Update the minimum deposit to `minimumDeposit` Graph Tokens
     * @param minimumDeposit The minimum deposit in Graph Tokens
     */
    function setMinimumDeposit(uint256 minimumDeposit) external;

    /**
     * @dev Set the percent reward that the fisherman gets when slashing occurs.
     * @notice Update the reward percentage to `percentage`
     * @param percentage Reward as a percentage of indexer stake
     */
    function setFishermanRewardPercentage(uint32 percentage) external;

    /**
     * @notice Set the percentage used for slashing indexers.
     * @param qryPercentage Percentage slashing for query disputes
     * @param idxPercentage Percentage slashing for indexing disputes
     */
    function setSlashingPercentage(uint32 qryPercentage, uint32 idxPercentage) external;

    // -- Getters --

    /**
     * @notice Check if a dispute has been created
     * @param disputeID Dispute identifier
     * @return True if the dispute exists
     */
    function isDisputeCreated(bytes32 disputeID) external view returns (bool);

    /**
     * @notice Encode a receipt into a hash for EIP-712 signature verification
     * @param receipt The receipt to encode
     * @return The encoded hash
     */
    function encodeHashReceipt(Receipt memory receipt) external view returns (bytes32);

    /**
     * @notice Check if two attestations are conflicting
     * @param attestation1 First attestation
     * @param attestation2 Second attestation
     * @return True if attestations are conflicting
     */
    function areConflictingAttestations(
        Attestation memory attestation1,
        Attestation memory attestation2
    ) external pure returns (bool);

    /**
     * @notice Get the indexer address from an attestation
     * @param attestation The attestation to extract indexer from
     * @return The indexer address
     */
    function getAttestationIndexer(Attestation memory attestation) external view returns (address);

    // -- Dispute --

    /**
     * @notice Create a query dispute for the arbitrator to resolve.
     * This function is called by a fisherman that will need to `deposit` at
     * least `minimumDeposit` GRT tokens.
     * @param attestationData Attestation bytes submitted by the fisherman
     * @param deposit Amount of tokens staked as deposit
     * @return The dispute ID
     */
    function createQueryDispute(bytes calldata attestationData, uint256 deposit) external returns (bytes32);

    /**
     * @notice Create query disputes for two conflicting attestations.
     * A conflicting attestation is a proof presented by two different indexers
     * where for the same request on a subgraph the response is different.
     * For this type of dispute the submitter is not required to present a deposit
     * as one of the attestation is considered to be right.
     * Two linked disputes will be created and if the arbitrator resolve one, the other
     * one will be automatically resolved.
     * @param attestationData1 First attestation data submitted
     * @param attestationData2 Second attestation data submitted
     * @return First dispute ID
     * @return Second dispute ID
     */
    function createQueryDisputeConflict(
        bytes calldata attestationData1,
        bytes calldata attestationData2
    ) external returns (bytes32, bytes32);

    /**
     * @notice Create an indexing dispute
     * @param allocationID Allocation ID being disputed
     * @param deposit Deposit amount for the dispute
     * @return The dispute ID
     */
    function createIndexingDispute(address allocationID, uint256 deposit) external returns (bytes32);

    /**
     * @notice Accept a dispute (arbitrator only)
     * @param disputeID ID of the dispute to accept
     */
    function acceptDispute(bytes32 disputeID) external;

    /**
     * @notice Reject a dispute (arbitrator only)
     * @param disputeID ID of the dispute to reject
     */
    function rejectDispute(bytes32 disputeID) external;

    /**
     * @notice Draw a dispute (arbitrator only)
     * @param disputeID ID of the dispute to draw
     */
    function drawDispute(bytes32 disputeID) external;
}
