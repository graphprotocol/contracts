pragma solidity 0.6.7;
pragma experimental "ABIEncoderV2";

import "../../adjudicator/ChallengeRegistry.sol";
import "../../adjudicator/interfaces/CounterfactualApp.sol";


/// @notice TimeLockedPassThrough - Before `switchesOutcomeAt`, this contract
/// should return the exact same outcome as the outcome `targetAppIdentityHash`
///  returns, allowing it to "pass through" unaltered.
///
/// However, after `switchesOutcomeAt`, it should return `defaultOutcome`.
/// `challengeRegistryAddress` is used to look up the outcome.
///
/// This contract is applied to virtual apps for two reasons:
///
/// 1. After the pre-agreed intermediation period elapses, the outcome
///    must be fixed to the default (cannot be changed without
///    the intermediary's consent) to allow them to safely get back their
///    collateral.
///
/// 2. During the installation and uninstallation of the virtual app,
///    this contract must be set to the default outcome, so that if funding
///    fails halfway, the intermediary can dispute both channels safely
contract TimeLockedPassThrough {

    struct AppState {
        address challengeRegistryAddress;
        bytes32 targetAppIdentityHash;
        uint256 switchesOutcomeAt;
        bytes defaultOutcome;
    }

    function computeOutcome(bytes calldata encodedState)
        external
        view
        returns (bytes memory)
    {
        AppState memory appState = abi.decode(encodedState, (AppState));

        if (block.number >= appState.switchesOutcomeAt) {
            return appState.defaultOutcome;
        }

        return ChallengeRegistry(
            appState.challengeRegistryAddress
        ).getOutcome(
            appState.targetAppIdentityHash
        );
    }
}
