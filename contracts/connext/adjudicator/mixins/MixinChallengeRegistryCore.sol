pragma solidity 0.5.11;
pragma experimental "ABIEncoderV2";

import "../libs/LibStateChannelApp.sol";
import "./MChallengeRegistryCore.sol";


/// @title MixinChallengeRegistryCore
/// @author Liam Horne - <liam@l4v.io>
/// @notice Core functionality and utilities for the ChallengeRegistry
contract MixinChallengeRegistryCore is MChallengeRegistryCore {

    /// @notice A getter function for the current AppChallenge state
    /// @param identityHash The unique hash of an `AppIdentity`
    /// @return A `AppChallenge` object representing the state of the on-chain challenge
    function getAppChallenge(bytes32 identityHash)
        external
        view
        returns (AppChallenge memory)
    {
        return appChallenges[identityHash];
    }

    /// @notice A getter function for the outcome if one is set
    /// @param identityHash The unique hash of an `AppIdentity`
    /// @return A `Transfer.Transaction` object representing the outcome of the channel
    function getOutcome(bytes32 identityHash)
        external
        view
        returns (bytes memory)
    {
        AppChallenge storage challenge = appChallenges[identityHash];
        require(
            isOutcomeSet(challenge),
            "Outcome hasn't been set yet"
        );

        return appOutcomes[identityHash];
    }

}
