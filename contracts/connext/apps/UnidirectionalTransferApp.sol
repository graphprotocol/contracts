pragma solidity 0.5.11;
pragma experimental "ABIEncoderV2";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../adjudicator/interfaces/CounterfactualApp.sol";
import "../funding/libs/LibOutcome.sol";


/// @title Unidirectional Transfer App
/// @notice This contract allows unidirectional coin transfers using the
///         takeAction paradigm.
contract UnidirectionalTransferApp is CounterfactualApp {

    using SafeMath for uint256;

    /**
      * The state machine is as follows:
      *
      *  turnNum =
      *
      *      0                  1                   2
      *
      * [ POST_FUND ] -> [ MONEY_SENT ] -> [[ CHANNEL_CLOSED ]]
      *
      *           SEND_MONEY          END_CHANNEL
      *         only by sender        by receiver
      *
      *                           1
      *
      *               -> [[ CHANNEL_CLOSED ]]
      *
      *                       END_CHANNEL
      *                        by sender
      *
      * [[ ]] represents a "terminal" state, where finalized = true.
      *
      * The lifecycle is as follows:
      *
      * 1. App is installed by both parties. Sender puts in TWO.
      *
      *    channelState = (
      *      participants = [sender, recipient],
      *      state = {
      *        transfers: [to: sender, TWO], [to: recipient, ZERO]
      *        turnNum = 0,
      *        finalized = false
      *      }
      *    )
      *
      * 2. The sender wants to send money. Takes Action(SEND_MONEY, ONE)
      *
      *    channelState = (
      *      participants = [sender, recipient],
      *      state = {
      *        transfers: [to: sender, ONE], [to: recipient, ONE]
      *        turnNum = 1,
      *        finalized = false
      *      }
      *    )
      *
      * 2. The sender wants to send _more_ money. Takes Action(SEND_MONEY, ONE)
      *
      *    channelState = (
      *      participants = [sender, recipient],
      *      state = {
      *        transfers: [to: sender, ZERO], [to: recipient, TWO]
      *        turnNum = 1,
      *        finalized = false
      *      }
      *    )
      *
      *    Note, this means the recipient can choose which one they want.
      *
      * 3. Receiver wants to finish this. Take Action(END_CHANNEL)
      *
      *    channelState = (
      *      participants = [sender, recipient],
      *      state = {
      *        transfers: [to: sender, ZERO], [to: recipient, TWO]
      *        turnNum = 2,
      *        finalized = true
      *      }
      *    )
      *
      */

    enum AppStage {
        POST_FUND,
        MONEY_SENT,
        CHANNEL_CLOSED
    }

    struct AppState {
        AppStage stage;
        LibOutcome.CoinTransfer[2] transfers;
        // NOTE: These following parameters are soon
        //       to be built in as framework-level
        //       constants but for now must be app-level.
        uint256 turnNum;
        bool finalized;
    }

    enum ActionType {
        SEND_MONEY,
        // NOTE: These following action will soon
        //       be built in as a framework-level
        //       constant but for now must be app-level.
        END_CHANNEL
    }

    struct Action {
        ActionType actionType;
        uint256 amount;
    }

    function getTurnTaker(
        bytes calldata encodedState,
        address[] calldata participants
    )
        external
        view
        returns (address)
    {
        return participants[
            abi.decode(encodedState, (AppState)).turnNum % participants.length
        ];
    }

    function computeOutcome(bytes calldata encodedState)
        external
        view
        returns (
          bytes memory // Encoded version of a LibOutcome.CoinTransfer[2]
        )
    {
        return abi.encode(abi.decode(encodedState, (AppState)).transfers);
    }

    function applyAction(
        bytes calldata encodedState,
        bytes calldata encodedAction
    )
        external
        view
        returns (bytes memory)
    {
        AppState memory state = abi.decode(
            encodedState,
            (AppState)
        );

        Action memory action = abi.decode(
            encodedAction,
            (Action)
        );

        /**
         * Anyone can close the channel at any time.
         */
        if (action.actionType == ActionType.END_CHANNEL) {
            return abi.encode(
                AppState(
                    /* stage */
                    AppStage.CHANNEL_CLOSED,
                    /* transfers */
                    state.transfers,
                    /* turnNum */
                    state.turnNum + 1,
                    /* finalized */
                    true
                )
            );
        }

        if (state.stage == AppStage.POST_FUND) {
            if (action.actionType == ActionType.SEND_MONEY) {
                return abi.encode(
                    AppState(
                        /* stage */
                        AppStage.MONEY_SENT,
                        /* transfers */
                        LibOutcome.CoinTransfer[2]([
                            LibOutcome.CoinTransfer(
                                state.transfers[0].to,
                                state.transfers[0].amount.sub(action.amount)
                            ),
                            LibOutcome.CoinTransfer(
                                state.transfers[1].to,
                                state.transfers[1].amount.add(action.amount)
                            )
                        ]),
                        /* turnNum */
                        state.turnNum + 1,
                        /* finalized */
                        false
                      )
                );
            }

            revert(
                "Invalid action. Valid actions from POST_FUND are {SEND_MONEY, END_CHANNEL}"
            );
        }

        revert("Invalid action. Valid actions from MONEY_SENT are {END_CHANNEL}");

    }

    function isStateTerminal(bytes calldata encodedState)
        external
        view
        returns (bool)
    {
        return abi.decode(encodedState, (AppState)).finalized;
    }

}
