pragma solidity 0.5.11;
pragma experimental "ABIEncoderV2";

import "../libs/LibStateChannelApp.sol";
import "./MChallengeRegistryCore.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";


contract MixinProgressState is LibStateChannelApp, MChallengeRegistryCore {

    using SafeMath for uint256;

    /// @notice Progress state with a unilateral action on the stored state
    /// @param appIdentity An AppIdentity object
    /// @param req A signed app challenge update that contains the resulting state,
    ///        i.e. the state that results from applying the given action to the stored state
    /// @param oldAppState The ABI encoded state that corresponds to the stored hash
    /// @param action The abi-encoded action to be taken on oldAppState
    function progressState(
        AppIdentity memory appIdentity,
        SignedAppChallengeUpdate memory req,
        bytes memory oldAppState,
        bytes memory action
    )
        public
    {
        bytes32 identityHash = appIdentityToHash(appIdentity);
        AppChallenge storage challenge = appChallenges[identityHash];

        require(
            isProgressable(challenge, appIdentity.defaultTimeout),
            "progressState called on app not in a progressable state"
        );

        bytes32 oldAppStateHash = appStateToHash(oldAppState);

        require(
            oldAppStateHash == challenge.appStateHash,
            "progressState called with oldAppState that does not match stored challenge"
        );

        address turnTaker = getTurnTaker(
            appIdentity.appDefinition,
            appIdentity.participants,
            oldAppState
        );

        // Build an array that contains only the turn-taker
        address[] memory signers = new address[](1);
        signers[0] = turnTaker;

        require(
            correctKeysSignedAppChallengeUpdate(
                identityHash,
                signers,
                req
            ),
            "Call to progressState included incorrectly signed state update"
        );

        // This should throw an error if reverts
        bytes memory newAppState = applyAction(
            appIdentity.appDefinition,
            oldAppState,
            action
        );

        bytes32 newAppStateHash = appStateToHash(newAppState);

        require(
            newAppStateHash == req.appStateHash,
            "progressState: applying action to old state does not match new state"
        );

        require(
            req.versionNumber == challenge.versionNumber.add(1),
            "progressState: versionNumber of new state is not that of stored state plus 1"
        );

        // Update challenge
        challenge.status = ChallengeStatus.IN_ONCHAIN_PROGRESSION;
        challenge.appStateHash = newAppStateHash;
        challenge.versionNumber = req.versionNumber;
        challenge.finalizesAt = block.number.add(appIdentity.defaultTimeout);

        // Check whether state is terminal, for immediate finalization (could be optional)
        if (isStateTerminal(appIdentity.appDefinition, newAppState)) {
            challenge.status = ChallengeStatus.EXPLICITLY_FINALIZED;
        }

        emit StateProgressed(
            identityHash,
            action,
            req.versionNumber,
            req.timeout,
            turnTaker,
            req.signatures[0]
        );

        emit ChallengeUpdated(
            identityHash,
            challenge.status,
            challenge.appStateHash,
            challenge.versionNumber,
            challenge.finalizesAt
        );
    }

}
