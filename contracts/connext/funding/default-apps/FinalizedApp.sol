pragma solidity 0.5.11;
pragma experimental "ABIEncoderV2";

import "./IdentityApp.sol";


contract FinalizedApp is IdentityApp {

    function isStateTerminal(bytes calldata)
        external
        view
        returns (bool)
    {
        return true;
    }

}
