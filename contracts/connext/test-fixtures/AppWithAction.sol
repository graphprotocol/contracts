pragma solidity ^0.6.4;
pragma experimental "ABIEncoderV2";

import "@connext/contracts/src.sol/adjudicator/interfaces/CounterfactualApp.sol";
import "@connext/contracts/src.sol/funding/libs/LibOutcome.sol";


/*
 * App with a counter
 * Only participants[1] is allowed to increment it
 */
contract AppWithAction is CounterfactualApp {
    enum ActionType { SUBMIT_COUNTER_INCREMENT, ACCEPT_INCREMENT }

    struct State {
        uint256 counter;
        LibOutcome.CoinTransfer[2] transfers;
    }

    struct Action {
        ActionType actionType;
        uint256 increment;
    }

    /**
     * The 0th signer is allowed to make one nonzero increment at turnNum = 0,
     * after which time the 1st signer may finalize the outcome.
     */
    function getTurnTaker(bytes calldata encodedState, address[] calldata participants)
        external
        override
        view
        returns (address)
    {
        State memory state = abi.decode(encodedState, (State));
        return participants[state.counter > 0 ? 0 : 1];
    }

    /// @dev NOTE: there is a slight difference here vs. the connext
    ///      AppWithCounter contract. Specifically, we want this app to
    ///      use the SingleAssetTwoPartyCoinTransferInterpreter
    function computeOutcome(bytes calldata encodedState)
        external
        virtual
        override
        view
        returns (bytes memory)
    {
        State memory state = abi.decode(encodedState, (State));

        return abi.encode(state.transfers);
    }

    function applyAction(bytes calldata encodedState, bytes calldata encodedAction)
        external
        virtual
        override
        view
        returns (bytes memory ret)
    {
        State memory state = abi.decode(encodedState, (State));
        Action memory action = abi.decode(encodedAction, (Action));

        if (action.actionType == ActionType.SUBMIT_COUNTER_INCREMENT) {
            require(action.increment > 0, "Increment must be nonzero");
            state.counter += action.increment;
        } else if (action.actionType != ActionType.ACCEPT_INCREMENT) {
            revert("Unknown actionType");
        }

        return abi.encode(state);
    }

    function isStateTerminal(bytes calldata encodedState) external override view returns (bool) {
        State memory state = abi.decode(encodedState, (State));
        return state.counter > 5;
    }
}
