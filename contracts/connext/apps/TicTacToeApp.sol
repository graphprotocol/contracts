pragma solidity 0.6.7;
pragma experimental "ABIEncoderV2";

import "../adjudicator/interfaces/CounterfactualApp.sol";
import "../funding/libs/LibOutcome.sol";


contract TicTacToeApp is CounterfactualApp {

    enum ActionType {
        PLAY,
        PLAY_AND_WIN,
        PLAY_AND_DRAW,
        DRAW
    }

    enum WinClaimType {
        COL,
        ROW,
        DIAG,
        CROSS_DIAG
    }

    struct WinClaim {
        WinClaimType winClaimType;
        uint256 idx;
    }

    // Constants for AppState::winner.
    // If i = AppState::winner is not one of these, then
    // players[i-1] has won.
    uint256 constant GAME_IN_PROGRESS = 0;
    uint256 constant GAME_DRAWN = 3;

    // Constants for elements of AppState::board
    // If i = AppState::board[x][y] is not one of these, then
    // players[i-1] has played on (x, y)
    uint256 constant EMPTY_SQUARE = 0;

    struct AppState {
        uint256 versionNumber; // NOTE: This field is mandatory, do not modify!
        uint256 winner;
        uint256[3][3] board;
    }

    struct Action {
        ActionType actionType;
        uint256 playX;
        uint256 playY;
        WinClaim winClaim;
    }

    function isStateTerminal(bytes calldata encodedState)
        override
        external
        view
        returns (bool)
    {
        AppState memory state = abi.decode(encodedState, (AppState));
        return state.winner != GAME_IN_PROGRESS;
    }

    // NOTE: Function is being deprecated soon, do not modify!
    function getTurnTaker(
        bytes calldata encodedState,
        address[] calldata participants
    )
        override
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
        override
        external
        view
        returns (bytes memory)
    {
        AppState memory state = abi.decode(encodedState, (AppState));
        Action memory action = abi.decode(encodedAction, (Action));

        AppState memory postState;
        if (action.actionType == ActionType.PLAY) {
            postState = playMove(
                state,
                state.versionNumber % 2,
                action.playX,
                action.playY
            );
        } else if (action.actionType == ActionType.PLAY_AND_WIN) {
            postState = playMove(
                state,
                state.versionNumber % 2,
                action.playX,
                action.playY
            );
            assertWin(state.versionNumber % 2, postState, action.winClaim);
            postState.winner = (postState.versionNumber % 2) + 1;
        } else if (action.actionType == ActionType.PLAY_AND_DRAW) {
            postState = playMove(
                state,
                state.versionNumber % 2,
                action.playX,
                action.playY
            );
            assertBoardIsFull(postState);
            postState.winner = 3;
        } else if (action.actionType == ActionType.DRAW) {
            assertBoardIsFull(state);
            postState = state;
            postState.winner = 3;
        }

        postState.versionNumber += 1;

        return abi.encode(postState);
    }

    function computeOutcome(bytes calldata encodedState)
      override
      external
      view
      returns (bytes memory)
    {
        AppState memory state = abi.decode(encodedState, (AppState));

        if (state.winner == 2) {
            return abi.encode(LibOutcome.TwoPartyFixedOutcome.SEND_TO_ADDR_TWO);
        } else if (state.winner == 1) {
            return abi.encode(LibOutcome.TwoPartyFixedOutcome.SEND_TO_ADDR_ONE);
        } else if (state.winner == GAME_DRAWN) {
            return abi.encode(LibOutcome.TwoPartyFixedOutcome.SPLIT_AND_SEND_TO_BOTH_ADDRS);
        } else {
            if (state.versionNumber % 2 == 0) {
                return abi.encode(LibOutcome.TwoPartyFixedOutcome.SEND_TO_ADDR_ONE);
            } else if (state.versionNumber % 2 == 1) {
                return abi.encode(LibOutcome.TwoPartyFixedOutcome.SEND_TO_ADDR_TWO);
            }
        }
    }

    function playMove(
        AppState memory state,
        uint256 playerId,
        uint256 x,
        uint256 y
    )
        internal
        pure
        returns (AppState memory)
    {
        require(state.board[x][y] == 0, "playMove: square is not empty");
        require(
            playerId == 0 || playerId == 1, "playMove: playerId not in range [0, 1]"
        );

        state.board[x][y] = playerId + 1;

        return state;
    }

    function assertBoardIsFull(AppState memory preState)
        internal
        pure
    {
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = 0; j < 3; j++) {
                require(
                    preState.board[i][j] != 0, "assertBoardIsFull: square is empty"
                );
            }
        }
    }

    function assertWin(
        uint256 playerId,
        AppState memory state,
        WinClaim memory winClaim
    )
        internal
        pure
    {
        uint256 expectedSquareState = playerId + 1;
        if (winClaim.winClaimType == WinClaimType.COL) {
            require(
                state.board[winClaim.idx][0] == expectedSquareState, "Win Claim not valid"
            );
            require(
                state.board[winClaim.idx][1] == expectedSquareState, "Win Claim not valid"
            );
            require(
                state.board[winClaim.idx][2] == expectedSquareState, "Win Claim not valid"
            );
        } else if (winClaim.winClaimType == WinClaimType.ROW) {
            require(
                state.board[0][winClaim.idx] == expectedSquareState, "Win Claim not valid"
            );
            require(
                state.board[1][winClaim.idx] == expectedSquareState, "Win Claim not valid"
            );
            require(
                state.board[2][winClaim.idx] == expectedSquareState, "Win Claim not valid"
            );
        } else if (winClaim.winClaimType == WinClaimType.DIAG) {
            require(state.board[0][0] == expectedSquareState, "Win Claim not valid");
            require(state.board[1][1] == expectedSquareState, "Win Claim not valid");
            require(state.board[2][2] == expectedSquareState, "Win Claim not valid");
        } else if (winClaim.winClaimType == WinClaimType.CROSS_DIAG) {
            require(state.board[2][0] == expectedSquareState, "Win Claim not valid");
            require(state.board[1][1] == expectedSquareState, "Win Claim not valid");
            require(state.board[0][2] == expectedSquareState, "Win Claim not valid");
        }
    }

}
