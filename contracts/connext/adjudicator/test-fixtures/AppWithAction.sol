pragma solidity 0.5.11;
pragma experimental "ABIEncoderV2";

import "../interfaces/CounterfactualApp.sol";


/*
 * App with a counter
 * Only participants[1] is allowed to increment it
 */
contract AppWithAction is CounterfactualApp {

    enum TwoPartyFixedOutcome {
        SEND_TO_ADDR_ONE,
        SEND_TO_ADDR_TWO,
        SPLIT_AND_SEND_TO_BOTH_ADDRS
    }

    enum ActionType { SUBMIT_COUNTER_INCREMENT, ACCEPT_INCREMENT }

    struct State {
        uint256 counter;
    }

    struct Action {
        ActionType actionType;
        uint256 increment;
    }

    /**
     * The 0th signer is allowed to make one nonzero increment at turnNum = 0,
     * after which time the 1st signer may finalize the outcome.
     */
    function getTurnTaker(
        bytes calldata encodedState,
        address[] calldata participants
    )
        external
        view
        returns (address)
    {
        State memory state = abi.decode(encodedState, (State));
        return participants[state.counter > 0 ? 0 : 1];
    }

    function computeOutcome(bytes calldata)
        external
        view
        returns (bytes memory)
    {
        return abi.encode(TwoPartyFixedOutcome.SEND_TO_ADDR_ONE);
    }

    function applyAction(
        bytes calldata encodedState,
        bytes calldata encodedAction
    )
        external
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

    function isStateTerminal(bytes calldata encodedState)
        external
        view
        returns (bool)
    {
        State memory state = abi.decode(encodedState, (State));
        return state.counter > 5;
    }

}
