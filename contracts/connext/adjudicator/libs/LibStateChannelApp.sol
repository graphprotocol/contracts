pragma solidity 0.5.11;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../../shared/libs/LibChannelCrypto.sol";
import "./LibDispute.sol";

/// @title LibStateChannelApp
/// @author Liam Horne - <liam@l4v.io>
/// @notice Contains the structures and enums needed when disputing apps
contract LibStateChannelApp is LibDispute {

    using LibChannelCrypto for bytes32;
    using SafeMath for uint256;

    // A minimal structure that uniquely identifies a single instance of an App
    struct AppIdentity {
        address multisigAddress;
        uint256 channelNonce;
        address[] participants;
        address appDefinition;
        uint256 defaultTimeout;
    }

    // A structure representing the state of a CounterfactualApp instance from the POV of the blockchain
    // NOTE: AppChallenge is the overall state of a channelized app instance,
    // appStateHash is the hash of a state specific to the CounterfactualApp (e.g. chess position)
    struct AppChallenge {
        ChallengeStatus status;
        bytes32 appStateHash;
        uint256 versionNumber;
        uint256 finalizesAt;
    }

    /// @dev Checks whether the given timeout has passed
    /// @param timeout a timeout as block number
    function hasPassed(
        uint256 timeout
    )
        public
        view
        returns (bool)
    {
        return timeout <= block.number;
    }

    /// @dev Checks whether it is still possible to send all-party-signed states
    /// @param appChallenge the app challenge to check
    function isDisputable(
        AppChallenge memory appChallenge
    )
        public
        view
        returns (bool)
    {
        return appChallenge.status == ChallengeStatus.NO_CHALLENGE ||
            (
                appChallenge.status == ChallengeStatus.IN_DISPUTE &&
                !hasPassed(appChallenge.finalizesAt)
            );
    }

    /// @dev Checks an outcome for a challenge has been set
    /// @param appChallenge the app challenge to check
    function isOutcomeSet(
        AppChallenge memory appChallenge
    )
        public
        view
        returns (bool)
    {
        return appChallenge.status == ChallengeStatus.OUTCOME_SET;
    }

    /// @dev Checks whether it is possible to send actions to progress state
    /// @param appChallenge the app challenge to check
    /// @param defaultTimeout the app instance's default timeout
    function isProgressable(
        AppChallenge memory appChallenge,
        uint256 defaultTimeout
    )
        public
        view
        returns (bool)
    {
        return
            (
                appChallenge.status == ChallengeStatus.IN_DISPUTE &&
                hasPassed(appChallenge.finalizesAt) &&
                !hasPassed(appChallenge.finalizesAt.add(defaultTimeout))
            ) ||
            (
                appChallenge.status == ChallengeStatus.IN_ONCHAIN_PROGRESSION &&
                !hasPassed(appChallenge.finalizesAt)
            );
    }

    /// @dev Checks whether it is possible to cancel a given challenge
    /// @param appChallenge the app challenge to check
    /// @param defaultTimeout the app instance's default timeout
    function isCancellable(
        AppChallenge memory appChallenge,
        uint256 defaultTimeout
    )
        public
        view
        returns (bool)
    {
        // Note: we also initially allowed cancelling a dispute during
        //       the dispute phase but before timeout had expired.
        //       TODO: does that make sense to add back in?
        return isProgressable(appChallenge, defaultTimeout);
    }

    /// @dev Checks whether the state is finalized
    /// @param appChallenge the app challenge to check
    /// @param defaultTimeout the app instance's default timeout
    function isFinalized(
        AppChallenge memory appChallenge,
        uint256 defaultTimeout
    )
        public
        view
        returns (bool)
    {
        return (
          (
              appChallenge.status == ChallengeStatus.IN_DISPUTE &&
              hasPassed(appChallenge.finalizesAt.add(defaultTimeout))
          ) ||
          (
              appChallenge.status == ChallengeStatus.IN_ONCHAIN_PROGRESSION &&
              hasPassed(appChallenge.finalizesAt)
          ) ||
          (
              appChallenge.status == ChallengeStatus.EXPLICITLY_FINALIZED
          )
        );
    }

    /// @dev Verifies signatures given the signer addresses
    /// @param signatures message `txHash` signature
    /// @param txHash operation ethereum signed message hash
    /// @param signers addresses of all signers in order
    function verifySignatures(
        bytes[] memory signatures,
        bytes32 txHash,
        address[] memory signers
    )
        public
        pure
        returns (bool)
    {
        require(
            signers.length == signatures.length,
            "Signers and signatures should be of equal length"
        );
        for (uint256 i = 0; i < signers.length; i++) {
            require(
                signers[i] == txHash.verifyChannelMessage(signatures[i]),
                "Invalid signature"
            );
        }
        return true;
    }

}
