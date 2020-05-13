pragma solidity 0.6.7;
pragma experimental "ABIEncoderV2";


interface CounterfactualAppInterface {

    function isStateTerminal(bytes calldata)
        external
        view
        returns (bool);

    function getTurnTaker(bytes calldata, address[] calldata)
        external
        view
        returns (address);

    function applyAction(bytes calldata, bytes calldata)
        external
        view
        returns (bytes memory);

    function computeOutcome(bytes calldata)
        external
        view
        returns (bytes memory);

}
