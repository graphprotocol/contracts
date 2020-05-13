pragma solidity 0.6.7;
pragma experimental "ABIEncoderV2";

import "./AppWithAction.sol";


/*
 * App with a counter
 * Only participants[1] is allowed to increment it
 */
contract AppComputeOutcomeFails is AppWithAction {

    function computeOutcome(bytes calldata)
        override
        external
        view
        returns (bytes memory)
    {
        revert("computeOutcome always fails for this app");
    }
}
