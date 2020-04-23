pragma solidity 0.5.11;
pragma experimental "ABIEncoderV2";

import "../libs/LibStateChannelApp.sol";
import "../libs/LibAppCaller.sol";
import "./MChallengeRegistryCore.sol";


contract MixinSetOutcome is LibStateChannelApp, LibAppCaller, MChallengeRegistryCore {

    /// @notice Fetch and store the outcome of a state channel application
    /// @param appIdentity An AppIdentity pointing to the app having the outcome set
    /// @param finalState The ABI encoded version of the finalized application state
    /// @dev Note this function is only callable when the application has been finalized
    function setOutcome(
        AppIdentity memory appIdentity,
        bytes memory finalState
    )
        public
    {
        bytes32 identityHash = appIdentityToHash(appIdentity);

        AppChallenge storage challenge = appChallenges[identityHash];

        require(
            isFinalized(challenge, appIdentity.defaultTimeout),
            "setOutcome can only be called after a challenge has been finalized"
        );

        require(
            !isOutcomeSet(challenge),
            "setOutcome called on challenge with outcome already set"
        );

        require(
            keccak256(finalState) == challenge.appStateHash,
            "setOutcome called with incorrect witness data of finalState"
        );

        appOutcomes[identityHash] = LibAppCaller.computeOutcome(
            appIdentity.appDefinition,
            finalState
        );
        challenge.status = ChallengeStatus.OUTCOME_SET;

        emit ChallengeUpdated(
            identityHash,
            challenge.status,
            challenge.appStateHash,
            challenge.versionNumber,
            challenge.finalizesAt
        );
    }

}
