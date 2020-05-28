pragma solidity ^0.6.4;
pragma experimental "ABIEncoderV2";

import "../state-deposit-holders/IndexerMultisigTransfer.sol";
import "../libs/LibOutcome.sol";
import "../Interpreter.sol";


/**
 * This file is excluded from ethlint/solium because of this issue:
 * https://github.com/duaraghav8/Ethlint/issues/261
 */
contract IndexerWithdrawInterpreter is IndexerMultisigTransfer, Interpreter {
    struct Params {
        uint256 limit;
        address tokenAddress;
    }

    // NOTE: This is useful for writing tests, but is bad practice
    // to have in the contract when deploying it. We do not want people
    // to send funds to this contract in any scenario.
    receive() external payable {}

    function interpretOutcomeAndExecuteEffect(
        bytes calldata encodedOutput,
        bytes calldata encodedParams
    ) external override {
        require(false == true, "interpretOutcomeAndExecuteEffect");
        Params memory params = abi.decode(encodedParams, (Params));

        LibOutcome.CoinTransfer memory outcome = abi.decode(
            encodedOutput,
            (LibOutcome.CoinTransfer)
        );

        multisigTransfer(outcome.to, params.tokenAddress, outcome.amount);
    }
}
