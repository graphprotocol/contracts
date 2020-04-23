pragma solidity 0.5.11;
pragma experimental ABIEncoderV2;


/// @title LibDispute
/// @notice Contains the structures and enums needed or generally useful in disputes
contract LibDispute {

    // The status of a challenge in the ChallengeRegistry
    enum ChallengeStatus {
        NO_CHALLENGE,
        IN_DISPUTE,
        IN_ONCHAIN_PROGRESSION,
        EXPLICITLY_FINALIZED,
        OUTCOME_SET
    }

    // State hash with version number and timeout, signed by all parties
    struct SignedAppChallengeUpdate {
        bytes32 appStateHash;
        uint256 versionNumber;
        uint256 timeout;
        bytes[] signatures;
    }

    // Used to cancel a challenge. Inc. current onchain state hash,
    // challenge status, and signatures on this
    struct SignedCancelDisputeRequest {
        uint256 versionNumber;
        bytes[] signatures;
    }

    // Event emitted when state is progressed via a unilateral action
    event StateProgressed (
      bytes32 identityHash,
      bytes action,
      uint256 versionNumber,
      uint256 timeout,
      address turnTaker,
      bytes signature
    );

    // Event emitted when the challenge is updated
    event ChallengeUpdated (
      bytes32 identityHash,
      ChallengeStatus status,
      bytes32 appStateHash,
      uint256 versionNumber,
      uint256 finalizesAt
    );
}
