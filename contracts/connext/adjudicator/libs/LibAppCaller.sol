pragma solidity 0.6.7;
pragma experimental "ABIEncoderV2";

import "../interfaces/CounterfactualApp.sol";


/// @title LibAppCaller
/// @author Liam Horne - <liam@l4v.io>
/// @notice A library for the ChallengeRegistry to make staticcalls to Apps
contract LibAppCaller {

    /// @notice A helper method to check if the state of an application is terminal or not
    /// @param appDefinition An address of an app definition to call
    /// @param appState The ABI encoded version of some application state
    /// @return A boolean indicating if the application state is terminal or not
    function isStateTerminal(
        address appDefinition,
        bytes memory appState
    )
        internal
        view
        returns (bool)
    {
        return CounterfactualApp(appDefinition).isStateTerminal(appState);
    }

    /// @notice A helper method to get the turn taker for an app
    /// @param appDefinition An address of an app definition to call
    /// @param appState The ABI encoded version of some application state
    /// @return An address representing the turn taker in the `participants`
    function getTurnTaker(
        address appDefinition,
        address[] memory participants,
        bytes memory appState
    )
        internal
        view
        returns (address)
    {
        return CounterfactualApp(appDefinition)
            .getTurnTaker(appState, participants);
    }

    /// @notice Execute the application's applyAction function to compute new state
    /// @param appDefinition An address of an app definition to call
    /// @param appState The ABI encoded version of some application state
    /// @param action The ABI encoded version of some application action
    /// @return A bytes array of the ABI encoded newly computed application state
    function applyAction(
        address appDefinition,
        bytes memory appState,
        bytes memory action
    )
        internal
        view
        returns (bytes memory)
    {
        return CounterfactualApp(appDefinition).applyAction(appState, action);
    }

    /// @notice Execute the application's computeOutcome function to compute an outcome
    /// @param appDefinition An address of an app definition to call
    /// @param appState The ABI encoded version of some application state
    function computeOutcome(
        address appDefinition,
        bytes memory appState
    )
        internal
        view
        returns (bytes memory)
    {
        return CounterfactualApp(appDefinition).computeOutcome(appState);
    }

}
