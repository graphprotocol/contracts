pragma solidity 0.5.11;
pragma experimental "ABIEncoderV2";

import "../../shared/libs/LibCommitment.sol";
import "../libs/LibStateChannelApp.sol";
import "../libs/LibAppCaller.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";


contract MChallengeRegistryCore is LibCommitment, LibStateChannelApp, LibAppCaller {

    using SafeMath for uint256;

    // A mapping of appIdentityHash to AppChallenge structs which represents
    // the current on-chain status of some particular application's state.
    mapping (bytes32 => AppChallenge) public appChallenges;

    // A mapping of appIdentityHash to outcomes
    mapping (bytes32 => bytes) public appOutcomes;

    /// @notice Compute a hash of an application's state
    /// @param appState The ABI encoded state
    /// @return A bytes32 hash of the state
    function appStateToHash(
        bytes memory appState
    )
        internal
        pure
        returns (bytes32)
    {
        return keccak256(appState);
    }

    /// @notice Compute a unique hash for a single instance of an App
    /// @param appIdentity An `AppIdentity` struct that encodes all unique info for an App
    /// @return A bytes32 hash of the AppIdentity
    function appIdentityToHash(
        AppIdentity memory appIdentity
    )
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                appIdentity.multisigAddress,
                appIdentity.channelNonce,
                keccak256(abi.encodePacked(appIdentity.participants)),
                appIdentity.appDefinition,
                appIdentity.defaultTimeout
            )
        );
    }

    /// @notice Compute a unique hash for the state of a channelized app instance
    /// @param identityHash The unique hash of an `AppIdentity`
    /// @param appStateHash The hash of the app state to be signed
    /// @param versionNumber The versionNumber corresponding to the version of the state
    /// @param timeout A dynamic timeout value representing the timeout for this state
    /// @return A bytes32 hash of the RLP encoded arguments
    function computeAppChallengeHash(
        bytes32 identityHash,
        bytes32 appStateHash,
        uint256 versionNumber,
        uint256 timeout
    )
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                uint8(CommitmentTarget.SET_STATE),
                identityHash,
                appStateHash,
                versionNumber,
                timeout
            )
        );
    }

    /// @notice Compute a unique hash for the state of a channelized app instance
    /// @param identityHash The unique hash of an `AppIdentity`
    /// @param versionNumber The versionNumber corresponding to the version of the state
    /// @return A bytes32 hash of the RLP encoded arguments
    function computeCancelDisputeHash(
        bytes32 identityHash,
        uint256 versionNumber
    )
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                uint8(CommitmentTarget.CANCEL_DISPUTE),
                identityHash,
                versionNumber
            )
        );
    }

    function correctKeysSignedAppChallengeUpdate(
        bytes32 identityHash,
        address[] memory participants,
        SignedAppChallengeUpdate memory req
    )
        public
        pure
        returns (bool)
    {
        bytes32 digest = computeAppChallengeHash(
            identityHash,
            req.appStateHash,
            req.versionNumber,
            req.timeout
        );

        return verifySignatures(
            req.signatures,
            digest,
            participants
        );
    }

}
