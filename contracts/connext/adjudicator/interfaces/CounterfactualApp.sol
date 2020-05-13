pragma solidity 0.6.7;
pragma experimental "ABIEncoderV2";

import "./CounterfactualAppInterface.sol";


contract CounterfactualApp is CounterfactualAppInterface {

    function isStateTerminal(bytes calldata)
        override
        virtual
        external
        view
        returns (bool)
    {
        revert("The isStateTerminal method has no implementation for this App");
    }

    function getTurnTaker(bytes calldata, address[] calldata)
        override
        virtual
        external
        view
        returns (address)
    {
        revert("The getTurnTaker method has no implementation for this App");
    }

    function applyAction(bytes calldata, bytes calldata)
        override
        virtual
        external
        view
        returns (bytes memory)
    {
        revert("The applyAction method has no implementation for this App");
    }

    function computeOutcome(bytes calldata)
        override
        virtual
        external
        view
        returns (bytes memory)
    {
        revert("The computeOutcome method has no implementation for this App");
    }

}
