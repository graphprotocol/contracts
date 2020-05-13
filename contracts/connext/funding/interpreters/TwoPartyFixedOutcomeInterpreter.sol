pragma solidity 0.6.7;
pragma experimental "ABIEncoderV2";

import "../state-deposit-holders/MultisigTransfer.sol";
import "../Interpreter.sol";
import "../libs/LibOutcome.sol";


/// @notice
/// Asset: Single Asset, ETH or ERC20
/// OutcomeType: TwoPartyFixedOutcome
/// The committed coins are sent to one of params.playerAddrs
/// or split in half according to the outcome
contract TwoPartyFixedOutcomeInterpreter is MultisigTransfer, Interpreter {

    struct Params {
        address payable[2] playerAddrs;
        uint256 amount;
        address tokenAddress;
    }

    function interpretOutcomeAndExecuteEffect(
        bytes calldata encodedOutcome,
        bytes calldata encodedParams
    )
        override
        external
    {
        LibOutcome.TwoPartyFixedOutcome outcome = abi.decode(
            encodedOutcome,
            (LibOutcome.TwoPartyFixedOutcome)
        );

        Params memory params = abi.decode(encodedParams, (Params));

        if (outcome == LibOutcome.TwoPartyFixedOutcome.SEND_TO_ADDR_ONE) {
            multisigTransfer(params.playerAddrs[0], params.tokenAddress, params.amount);
        } else if (outcome == LibOutcome.TwoPartyFixedOutcome.SEND_TO_ADDR_TWO) {
            multisigTransfer(params.playerAddrs[1], params.tokenAddress, params.amount);
        } else {
            /**
             * A functioning app should return SPLIT_AND_SEND_TO_BOTH_ADDRS
             * to indicate that the committed asset should be split, hence by right
             * we can revert here if the outcome is something other than that, since we
             * would have handled all cases; instead we choose to handle all other outcomes
             * as if they were SPLIT.
             */
            multisigTransfer(params.playerAddrs[0], params.tokenAddress, params.amount / 2);
            multisigTransfer(params.playerAddrs[1], params.tokenAddress, params.amount - params.amount / 2);
        }
    }

}
