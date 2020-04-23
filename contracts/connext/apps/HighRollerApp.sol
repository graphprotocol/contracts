pragma solidity 0.5.11;
pragma experimental "ABIEncoderV2";

import "../adjudicator/interfaces/CounterfactualApp.sol";
import "../funding/libs/LibOutcome.sol";


/// @title High Roller App
/// @notice This contract allows the playing of a dice rolling game.
///         Two players take turns rolling two dice each.
///         The winner is the player whose sum of dice outcomes is highest.
/// @dev This contract is an example of a dApp built to run on
///      the CounterFactual framework
contract HighRollerApp is CounterfactualApp {

    enum ActionType {
        COMMIT_TO_HASH,
        COMMIT_TO_NUM,
        REVEAL_NUM
    }

    enum Stage {
        WAITING_FOR_P1_COMMITMENT,
        P1_COMMITTED_TO_HASH,
        P2_COMMITTED_TO_NUM,
        P1_REVEALED_NUM,
        P1_TRIED_TO_SUBMIT_ZERO
    }

    enum Player {
        FIRST,
        SECOND
    }

    struct AppState {
        Stage stage;
        bytes32 salt;
        bytes32 commitHash;
        uint256 playerFirstNumber;
        uint256 playerSecondNumber;
        uint256 versionNumber; // NOTE: This field is mandatory, do not modify!
    }

    struct Action {
        ActionType actionType;
        uint256 number;
        bytes32 actionHash;
    }

    function isStateTerminal(bytes calldata encodedState)
        external
        view
        returns (bool)
    {
        AppState memory appState = abi.decode(encodedState, (AppState));
        return (
            appState.stage == Stage.P1_REVEALED_NUM ||
            appState.stage == Stage.P1_TRIED_TO_SUBMIT_ZERO
        );
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
        bytes calldata encodedState,
        bytes calldata encodedAction
    )
        external
        view
        returns (bytes memory)
    {
        AppState memory appState = abi.decode(encodedState, (AppState));
        Action memory action = abi.decode(encodedAction, (Action));

        AppState memory nextState = appState;

        if (action.actionType == ActionType.COMMIT_TO_HASH) {

            require(
                appState.stage == Stage.WAITING_FOR_P1_COMMITMENT,
                "Must apply COMMIT_TO_HASH to WAITING_FOR_P1_COMMITMENT"
            );

            nextState.stage = Stage.P1_COMMITTED_TO_HASH;
            nextState.commitHash = action.actionHash;

        } else if (action.actionType == ActionType.COMMIT_TO_NUM) {

            require(
                appState.stage == Stage.P1_COMMITTED_TO_HASH,
                "Must apply COMMIT_TO_NUM to P1_COMMITTED_TO_HASH"
            );

            require(
                action.number != 0,
                "It is considered invalid to use 0 as the number."
            );

            nextState.stage = Stage.P2_COMMITTED_TO_NUM;
            nextState.playerSecondNumber = action.number;

        } else if (action.actionType == ActionType.REVEAL_NUM) {

            require(
                appState.stage == Stage.P2_COMMITTED_TO_NUM,
                "Must apply REVEAL_NUM to P2_COMMITTED_TO_NUM"
            );

            bytes32 expectedCommitHash = keccak256(
                abi.encodePacked(action.actionHash, action.number)
            );

            require(
                expectedCommitHash == appState.commitHash,
                "Number presented by P1 was not what was previously committed to."
            );

            if (action.number == 0) {
                nextState.stage = Stage.P1_TRIED_TO_SUBMIT_ZERO;
            } else {
                nextState.stage = Stage.P1_REVEALED_NUM;
                nextState.playerFirstNumber = action.number;
                nextState.salt = action.actionHash;
            }

        } else {

            revert("Invalid action type");

        }

        nextState.versionNumber += 1;

        return abi.encode(nextState);
    }

    function computeOutcome(bytes calldata encodedState)
        external
        view
        returns (bytes memory)
    {
        AppState memory appState = abi.decode(encodedState, (AppState));

        // If P1 goes offline...
        if (appState.stage == Stage.WAITING_FOR_P1_COMMITMENT) {
            return abi.encode(LibOutcome.TwoPartyFixedOutcome.SEND_TO_ADDR_TWO);
        }

        // If P2 goes offline...
        if (appState.stage == Stage.P1_COMMITTED_TO_HASH) {
            return abi.encode(LibOutcome.TwoPartyFixedOutcome.SEND_TO_ADDR_ONE);
        }

        // If P1 goes offline...
        if (appState.stage == Stage.P2_COMMITTED_TO_NUM) {
            return abi.encode(LibOutcome.TwoPartyFixedOutcome.SEND_TO_ADDR_TWO);
        }

        // If P1 tried to cheat...
        if (appState.stage == Stage.P1_TRIED_TO_SUBMIT_ZERO) {
            return abi.encode(LibOutcome.TwoPartyFixedOutcome.SEND_TO_ADDR_TWO);
        }

        // Co-operative case
        return abi.encode(
            getWinningAmounts(
                appState.playerFirstNumber,
                appState.playerSecondNumber
            )
        );

    }

    function highRoller(bytes32 randomness)
        public
        view
        returns(uint8 playerFirstTotal, uint8 playerSecondTotal)
    {
        (
            uint8 playerFirstRollOne,
            uint8 playerFirstRollTwo,
            uint8 playerSecondRollOne,
            uint8 playerSecondRollTwo
        ) = getPlayerRolls(randomness);
        playerFirstTotal = playerFirstRollOne + playerFirstRollTwo;
        playerSecondTotal = playerSecondRollOne + playerSecondRollTwo;
    }

    function getPlayerRolls(bytes32 randomness)
        public // NOTE: This is used in app-root.tsx for the clientside dapp
        view
        returns(uint8 playerFirstRollOne, uint8 playerFirstRollTwo, uint8 playerSecondRollOne, uint8 playerSecondRollTwo)
    {
        (
            bytes8 hash1,
            bytes8 hash2,
            bytes8 hash3,
            bytes8 hash4
        ) = cutBytes32(randomness);
        playerFirstRollOne = bytes8toDiceRoll(hash1);
        playerFirstRollTwo = bytes8toDiceRoll(hash2);
        playerSecondRollOne = bytes8toDiceRoll(hash3);
        playerSecondRollTwo = bytes8toDiceRoll(hash4);
    }

    function getWinningAmounts(uint256 num1, uint256 num2)
        internal
        view
        returns (LibOutcome.TwoPartyFixedOutcome)
    {
        bytes32 randomSalt = calculateRandomSalt(num1, num2);

        (uint8 playerFirstTotal, uint8 playerSecondTotal) = highRoller(randomSalt);

        if (playerFirstTotal > playerSecondTotal) {
            return LibOutcome.TwoPartyFixedOutcome.SEND_TO_ADDR_ONE;
        }

        if (playerFirstTotal < playerSecondTotal) {
            return LibOutcome.TwoPartyFixedOutcome.SEND_TO_ADDR_TWO;
        }

        return LibOutcome.TwoPartyFixedOutcome.SPLIT_AND_SEND_TO_BOTH_ADDRS;

    }

    function calculateRandomSalt(uint256 num1, uint256 num2)
        internal
        view
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(num1 * num2));
    }

    /// @notice Splits a bytes32 into 4 bytes8 by cutting every 8 bytes
    /// @param h The bytes32 to be split
    /// @dev Takes advantage of implicitly recognizing the length of each bytes8
    ///      variable when being read by `mload`. We point to the start of each
    ///      string (e.g., 0x08, 0x10) by incrementing by 8 bytes each time.
    function cutBytes32(bytes32 h)
        internal
        view
        returns (bytes8 q1, bytes8 q2, bytes8 q3, bytes8 q4)
    {
        assembly {
            let ptr := mload(0x40)
            mstore(add(ptr, 0x00), h)
            q1 := mload(add(ptr, 0x00))
            q2 := mload(add(ptr, 0x08))
            q3 := mload(add(ptr, 0x10))
            q4 := mload(add(ptr, 0x18))
        }
    }

    /// @notice Converts a bytes8 into a uint64 between 1-6
    /// @param q The bytes8 to convert
    /// @dev Splits this by using modulo 6 to get the uint
    function bytes8toDiceRoll(bytes8 q)
      internal
      view
      returns (uint8)
    {
        return uint8(uint64(q) % 6);
    }

}
