pragma solidity 0.6.7;
pragma experimental "ABIEncoderV2";

import "../libs/LibStateChannelApp.sol";
import "./MChallengeRegistryCore.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";


contract MixinSetState is LibStateChannelApp, MChallengeRegistryCore {

    using SafeMath for uint256;

    /// @notice Set the instance state/AppChallenge to a given value.
    /// This value must have been signed off by all parties to the channel, that is,
    /// this must be called with the correct msg.sender (the state deposit holder)
    /// or signatures must be provided.
    /// @param appIdentity an AppIdentity struct with all information encoded within
    ///        it to represent which particular app is having state submitted
    /// @param req An object containing the update to be applied to the
    ///        applications state including the signatures of the users needed
    /// @dev This function is only callable when the state channel is not in challenge
    function setState(
        AppIdentity memory appIdentity,
        SignedAppChallengeUpdate memory req
    )
        public
    {
        bytes32 identityHash = appIdentityToHash(appIdentity);
        AppChallenge storage challenge = appChallenges[identityHash];

        require(
            isDisputable(challenge),
            "setState was called on an app that cannot be disputed anymore"
        );

        require(
            correctKeysSignedAppChallengeUpdate(
                identityHash,
                appIdentity.participants,
                req
            ),
            "Call to setState included incorrectly signed state update"
        );

        require(
            req.versionNumber > challenge.versionNumber,
            "setState was called with outdated state"
        );

        // Update challenge
        challenge.status = ChallengeStatus.IN_DISPUTE;
        challenge.appStateHash = req.appStateHash;
        challenge.versionNumber = req.versionNumber;
        challenge.finalizesAt = block.number.add(req.timeout);

        emit ChallengeUpdated(
            identityHash,
            challenge.status,
            challenge.appStateHash,
            challenge.versionNumber,
            challenge.finalizesAt
        );
    }

}
