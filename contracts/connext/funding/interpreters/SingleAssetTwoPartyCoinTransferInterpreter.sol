pragma solidity 0.5.11;
pragma experimental "ABIEncoderV2";

import "../state-deposit-holders/MultisigTransfer.sol";
import "../libs/LibOutcome.sol";
import "../Interpreter.sol";


/**
 * This file is excluded from ethlint/solium because of this issue:
 * https://github.com/duaraghav8/Ethlint/issues/261
 */
contract SingleAssetTwoPartyCoinTransferInterpreter is MultisigTransfer, Interpreter {

    struct Params {
        uint256 limit;
        address tokenAddress;
    }
    // NOTE: This is useful for writing tests, but is bad practice
    // to have in the contract when deploying it. We do not want people
    // to send funds to this contract in any scenario.
    function () external payable { }

    function interpretOutcomeAndExecuteEffect(
        bytes calldata encodedOutput,
        bytes calldata encodedParams
    )
        external
    {
        Params memory params = abi.decode(encodedParams, (Params));

        LibOutcome.CoinTransfer[2] memory outcome = abi.decode(
            encodedOutput,
            (LibOutcome.CoinTransfer[2])
        );

        multisigTransfer(outcome[0].to, params.tokenAddress, outcome[0].amount);
        multisigTransfer(outcome[1].to, params.tokenAddress, outcome[1].amount);
    }

}
