pragma solidity ^0.6.4;
pragma experimental "ABIEncoderV2";


interface Interpreter {
    function interpretOutcomeAndExecuteEffect(
        bytes calldata,
        bytes calldata
    )
        external;
}
