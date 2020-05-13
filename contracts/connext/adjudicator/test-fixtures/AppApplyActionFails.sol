pragma solidity 0.6.7;
pragma experimental "ABIEncoderV2";

import "./AppWithAction.sol";


/*
 * App with a counter
 * Only participants[1] is allowed to increment it. Apply action will always throw
 */
contract AppApplyActionFails is AppWithAction {

    function applyAction(
        bytes calldata /* encodedState */,
        bytes calldata /* encodedAction */
    )
        override
        external
        view
        returns (bytes memory)
    {
        revert("applyAction fails for this app");
    }

}
