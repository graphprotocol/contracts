pragma solidity 0.6.7;
pragma experimental "ABIEncoderV2";

import "../../shared/libs/LibChannelCrypto.sol";
import "../../adjudicator/interfaces/CounterfactualApp.sol";
import "../libs/LibOutcome.sol";


/// @title Withdraw App
/// @notice This contract allows a user to trustlessly generate a withdrawal
///         commitment by unlocking funds conditionally upon valid counterparty sig

///         THIS CONTRACT WILL ONLY WORK FOR 2-PARTY CHANNELS!
contract WithdrawApp is CounterfactualApp {
    using LibChannelCrypto for bytes32;

    struct AppState {
        // Note:
        // transfers[0].to == recipient;
        // transfers[0].amount == withdrawAmount;
        LibOutcome.CoinTransfer[2] transfers;
        bytes[2] signatures;
        address[2] signers; // must be multisig participants with withdrawer at [0]
        bytes32 data;
        bytes32 nonce;
        bool finalized;
    }

    struct Action {
        bytes signature;
    }

    function isStateTerminal(bytes calldata encodedState)
        override
        external
        view
        returns (bool)
    {
        AppState memory state = abi.decode(encodedState, (AppState));
        return state.finalized;
    }

    function getTurnTaker(
        bytes calldata encodedState,
        address[] calldata /* participants */
    )
        override
        external
        view
        returns (address)
    {
        AppState memory state = abi.decode(encodedState, (AppState));
        return state.signers[1];
    }

/// Assume that the initial state contains data, signers[], and signatures[0]
/// The action, then, must be called by the withdrawal counterparty who submits
/// their own signature on the withdrawal commitment data payload.
    function applyAction(
        bytes calldata encodedState,
        bytes calldata encodedAction
    )
        override
        external
        view
        returns (bytes memory)
    {
        AppState memory state = abi.decode(encodedState, (AppState));
        Action memory action = abi.decode(encodedAction, (Action));

        require(!state.finalized, "cannot take action on a finalized state");
        require(state.signers[0] == state.data.verifyChannelMessage(state.signatures[0]), "invalid withdrawer signature");
        require(state.signers[1] == state.data.verifyChannelMessage(action.signature), "invalid counterparty signature");

        state.signatures[1] = action.signature;
        state.finalized = true;

        return abi.encode(state);
    }

    function computeOutcome(bytes calldata encodedState)
        override
        external
        view
        returns (bytes memory)
    {
        AppState memory state = abi.decode(encodedState, (AppState));
        LibOutcome.CoinTransfer[2] memory transfers;

        if (state.finalized) {
            /**
             * If the state is finalized, zero out the withdrawer's balance
             */
            transfers = LibOutcome.CoinTransfer[2]([
                LibOutcome.CoinTransfer(
                    state.transfers[0].to,
                    /* should be set to 0 */
                    0
                ),
                LibOutcome.CoinTransfer(
                    state.transfers[1].to,
                    /* should always be 0 */
                    0
                )
            ]);
        } else {
            /**
             * If the state is not finalized, cancel the withdrawal
             */
            transfers = LibOutcome.CoinTransfer[2]([
                LibOutcome.CoinTransfer(
                    state.transfers[0].to,
                    state.transfers[0].amount
                ),
                LibOutcome.CoinTransfer(
                    state.transfers[1].to,
                    0
                )
            ]);
        }
        return abi.encode(transfers);
    }
}
