pragma solidity ^0.6.4;
pragma experimental "ABIEncoderV2";

/// @dev Allows for mocked testing of connext disputes.
///      All interfaces for disputes will remain the same,
///      and all functions should emit an event with the parameters
///      the function is called with. Functions within this contract
///      should perform as little work as possible to accurately
///      mock interctions with adjudicator contracts

import "@connext/contracts/src.sol/adjudicator/libs/LibStateChannelApp.sol";
import "@connext/contracts/src.sol/adjudicator/libs/LibAppCaller.sol";
import "@connext/contracts/src.sol/adjudicator/mixins/MixinChallengeRegistryCore.sol";


contract MockDispute is LibStateChannelApp, LibAppCaller, MixinChallengeRegistryCore {
    event SetStateAndOutcomeCalled(
        AppIdentity appIdentity,
        SignedAppChallengeUpdate req,
        bytes finalState
    );

    /// @notice Mocks the behavior of MixinSetState / MixinSetOutcome.
    ///         Short-circuits the dispute game by directly setting the
    ///         the outcome with the provided state.

    function setStateAndOutcome(
        AppIdentity memory appIdentity,
        SignedAppChallengeUpdate memory req,
        bytes memory finalState
    ) public {
        emit SetStateAndOutcomeCalled(appIdentity, req, finalState);

        // Update the challenge
        bytes32 identityHash = appIdentityToHash(appIdentity);
        AppChallenge storage challenge = appChallenges[identityHash];
        challenge.appStateHash = req.appStateHash;
        challenge.versionNumber = req.versionNumber;
        challenge.finalizesAt = block.number.add(req.timeout);
        challenge.status = ChallengeStatus.OUTCOME_SET;

        // Compute the outcome + set status
        appOutcomes[identityHash] = LibAppCaller.computeOutcome(
            appIdentity.appDefinition,
            finalState
        );

        // Emit the challenge updated event
        emit ChallengeUpdated(
            identityHash,
            challenge.status,
            challenge.appStateHash,
            challenge.versionNumber,
            challenge.finalizesAt
        );
    }
}
