pragma solidity 0.5.11;
pragma experimental "ABIEncoderV2";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../adjudicator/interfaces/CounterfactualApp.sol";
import "../funding/libs/LibOutcome.sol";


/// @title Unidirectional Linked Transfer App
/// @notice This contract allows users to claim a payment locked in
///         the application if they provide the correct preImage
contract UnidirectionalLinkedTransferApp is CounterfactualApp {

    using SafeMath for uint256;

    /**
    * Assume the app is funded with the money already owed to receiver,
    * as in the SimpleTwoPartySwapApp.
    *
    * This app can also not be used to send _multiple_ linked payments,
    * only one can be redeemed with the preImage.
    *
    */

    enum AppStage {
        POST_FUND,
        PAYMENT_CLAIMED,
        CHANNEL_CLOSED
    }

    struct AppState {
        AppStage stage;
        LibOutcome.CoinTransfer[2] transfers;
        bytes32 linkedHash;
        // NOTE: These following parameters are soon
        //       to be built in as framework-level
        //       constants but for now must be app-level.
        uint256 turnNum; // TODO: is this needed here?
        bool finalized;
    }

    // theres really only one type of action here,
    // the only reason to use the end channel action would
    // be to allow the hub to uninstall the app to reclaim
    // collateral. Since this can only be done while the recipient
    // is online, you dont *need* an END_CHANNEL action type, you
    // can just use an adjudicator.

    // Questions: if the app is set up to have the transfers pre-assigned
    // in the same way the swap app is atm, will the adjudicator know that
    // if no correct preImage is included in the commitment, it should 0
    // transfers?
    // enum ActionType {
    //   CLAIM_MONEY

    //   // // NOTE: These following action will soon
    //   // //       be built in as a framework-level
    //   // //       constant but for now must be app-level.
    //   // END_CHANNEL
    // }

    struct Action {
        uint256 amount;
        address assetId;
        bytes32 paymentId;
        bytes32 preImage;
    }

    function computeOutcome(bytes calldata encodedState)
        external
        view
        returns (bytes memory)
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

        bytes32 generatedHash = keccak256(
            abi.encodePacked(
                action.amount,
                action.assetId,
                action.paymentId,
                action.preImage
            )
        );
        if (generatedHash == state.linkedHash) {
            /**
             * If the hash is correct, finalize the state with provided transfers.
             */
            return abi.encode(
                AppState(
                    /* stage of app */
                    AppStage.PAYMENT_CLAIMED,
                    /* transfers */
                    LibOutcome.CoinTransfer[2]([
                        LibOutcome.CoinTransfer(
                            state.transfers[0].to,
                            /* should always be 0 */
                            state.transfers[1].amount
                        ),
                        LibOutcome.CoinTransfer(
                            state.transfers[1].to,
                            /* should always be full value of linked payment */
                            state.transfers[0].amount
                        )
                    ]),
                    /* link hash */
                    state.linkedHash,
                    /* turnNum */
                    state.turnNum + 1,
                    /* finalized */
                    true
                )
            );
        } else {
            /**
             * If the hash is not correct, finalize the state with reverted transfers.
             */
            return abi.encode(
                AppState(
                    /* stage of app */
                    AppStage.CHANNEL_CLOSED,
                    /* transfers */
                    LibOutcome.CoinTransfer[2]([
                        LibOutcome.CoinTransfer(
                            state.transfers[0].to,
                            state.transfers[0].amount
                        ),
                        LibOutcome.CoinTransfer(
                            state.transfers[1].to,
                            state.transfers[1].amount
                        )
                    ]),
                    /* link hash */
                    state.linkedHash,
                    /* turnNum */
                    state.turnNum + 1,
                    /* finalized */
                    true
                )
            );
        }
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

    function isStateTerminal(bytes calldata encodedState)
        external
        view
        returns (bool)
    {
        return abi.decode(encodedState, (AppState)).finalized;
    }

}
