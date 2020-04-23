pragma solidity 0.5.11;
pragma experimental "ABIEncoderV2";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../adjudicator/interfaces/CounterfactualApp.sol";
import "../funding/libs/LibOutcome.sol";


/// @title Simple Linked Transfer App
/// @notice This contract allows users to claim a payment locked in
///         the application if they provide the correct preImage
contract SimpleLinkedTransferApp is CounterfactualApp {

    using SafeMath for uint256;

    /**
    * Assume the app is funded with the money already owed to receiver,
    * as in the SimpleTwoPartySwapApp.
    *
    * This app can also not be used to send _multiple_ linked payments,
    * only one can be redeemed with the preImage.
    *
    */

    struct AppState {
        LibOutcome.CoinTransfer[2] coinTransfers;
        bytes32 linkedHash;
        // need these for computing outcome
        uint256 amount;
        address assetId;
        bytes32 paymentId;
        bytes32 preImage;
    }

    struct Action {
        bytes32 preImage;
    }

    function applyAction(
        bytes calldata encodedState,
        bytes calldata encodedAction
    )
        external
        view
        returns (bytes memory)
    {
        AppState memory state = abi.decode(encodedState, (AppState));
        Action memory action = abi.decode(encodedAction, (Action));

        state.preImage = action.preImage;

        return abi.encode(state);
    }

    function computeOutcome(bytes calldata encodedState)
        external
        view
        returns (bytes memory)
    {
        AppState memory state = abi.decode(encodedState, (AppState));
        // TODO: whats the protection against passing a different hash?

        bytes32 generatedHash = keccak256(
            abi.encodePacked(
                state.amount,
                state.assetId,
                state.paymentId,
                state.preImage
            )
        );

        LibOutcome.CoinTransfer[2] memory transfers;
        if (generatedHash == state.linkedHash) {
            /**
             * If the hash is correct, finalize the state with provided transfers.
             */
            transfers = LibOutcome.CoinTransfer[2]([
                LibOutcome.CoinTransfer(
                    state.coinTransfers[0].to,
                    /* should always be 0 */
                    0
                ),
                LibOutcome.CoinTransfer(
                    state.coinTransfers[1].to,
                    /* should always be full value of linked payment */
                    state.coinTransfers[0].amount
                )
            ]);
        } else {
            /**
             * If the hash is not correct, finalize the state with reverted transfers.
             */
            transfers = LibOutcome.CoinTransfer[2]([
                LibOutcome.CoinTransfer(
                    state.coinTransfers[0].to,
                    state.coinTransfers[0].amount
                ),
                LibOutcome.CoinTransfer(
                    state.coinTransfers[1].to,
                    0
                )
            ]);
        }
        return abi.encode(transfers);
    }
}
