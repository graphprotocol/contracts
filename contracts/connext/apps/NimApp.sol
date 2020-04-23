pragma solidity 0.5.11;
pragma experimental "ABIEncoderV2";

import "../adjudicator/interfaces/CounterfactualApp.sol";
import "../funding/libs/LibOutcome.sol";


/*
Normal-form Nim
https://en.wikipedia.org/wiki/Nim
*/
contract NimApp is CounterfactualApp {

    struct Action {
        uint256 pileIdx;
        uint256 takeAmnt;
    }

    struct AppState {
        uint256 versionNumber; // NOTE: This field is mandatory, do not modify!
        uint256[3] pileHeights;
    }

    function isStateTerminal(bytes calldata encodedState)
        external
        view
        returns (bool)
    {
        AppState memory state = abi.decode(encodedState, (AppState));
        return isWin(state);
    }

    // NOTE: Function is being deprecated soon, do not modify!
    function getTurnTaker(
        bytes calldata encodedState,
        address[] calldata participants
    )
        external
        view
        returns (address)
    {
        AppState memory state = abi.decode(encodedState, (AppState));
        return participants[state.versionNumber % 2];
    }

    function applyAction(
        bytes calldata encodedState, bytes calldata encodedAction
    )
        external
        view
        returns (bytes memory)
    {
        AppState memory state = abi.decode(encodedState, (AppState));
        Action memory action = abi.decode(encodedAction, (Action));

        require(action.pileIdx < 3, "pileIdx must be 0, 1 or 2");
        require(
            state.pileHeights[action.pileIdx] >= action.takeAmnt, "invalid pileIdx"
        );

        AppState memory ret = state;

        ret.pileHeights[action.pileIdx] -= action.takeAmnt;
        ret.versionNumber += 1;

        return abi.encode(ret);
    }

    function computeOutcome(bytes calldata encodedState)
        external
        view
        returns (bytes memory)
    {
        AppState memory state = abi.decode(encodedState, (AppState));

        if (state.versionNumber % 2 == 0) {
            return abi.encode(LibOutcome.TwoPartyFixedOutcome.SEND_TO_ADDR_ONE);
        } else {
            return abi.encode(LibOutcome.TwoPartyFixedOutcome.SEND_TO_ADDR_TWO);
        }
    }

    function isWin(AppState memory state)
        internal
        view
        returns (bool)
    {
        return (
            (state.pileHeights[0] == 0) && (state.pileHeights[1] == 0) && (state.pileHeights[2] == 0)
        );
    }


}
