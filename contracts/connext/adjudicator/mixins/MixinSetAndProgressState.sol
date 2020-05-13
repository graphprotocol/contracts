pragma solidity 0.6.7;
pragma experimental "ABIEncoderV2";

import "../libs/LibDispute.sol";
import "./MixinSetState.sol";
import "./MixinProgressState.sol";


contract MixinSetAndProgressState is LibDispute, MixinSetState, MixinProgressState {

    /// @notice Create a challenge regarding the latest signed state and immediately after,
    /// performs a unilateral action to update it; the latest signed state must have timeout 0
    /// @param appIdentity An AppIdentity object
    /// @param req1 A signed app challenge update that contains the hash of the latest state
    /// that has been signed by all parties; the timeout must be 0
    /// @param req2 A signed app challenge update that contains the state that results
    /// from applying the action to appState
    /// @param appState The full state whose hash is the state hash in req1
    /// @param action The abi-encoded action to be taken on appState
    function setAndProgressState(
        AppIdentity memory appIdentity,
        SignedAppChallengeUpdate memory req1,
        SignedAppChallengeUpdate memory req2,
        bytes memory appState,
        bytes memory action
    )
        public
    {
        setState(
            appIdentity,
            req1
        );

        progressState(
            appIdentity,
            req2,
            appState,
            action
        );

        // Maybe TODO:
        // This can be made slightly more efficient by doing _directly_
        // what these two functions do and leaving out unnecessary parts
        // like the intermediate storing of the challenge (before the
        // action has been applied to it) and skipping tests we know
        // must be true.
        // For now, this is the easiest and most convenient way, though.
    }

}
