pragma solidity ^0.5.1;

import "./GraphToken.sol";

contract A is ApproveAndCallFallBack {
    function receiveApproval(address from, uint256 tokens, address token, bytes memory data) public {
        BurnableERC20Token(token).tranferFrom(from, address(this), tokens);
        // do stuff...
    }
}
