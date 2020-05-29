pragma solidity ^0.6.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract MockStaking {
    IERC20 public token;

    constructor(IERC20 _token) public {
        token = _token;
    }

    mapping(address => bool) channels;

    function isChannel(address channelID) public view returns (bool) {
        return channels[channelID];
    }

    function setChannel(address channelID) public {
        channels[channelID] = true;
    }

    function settle(address indexer, uint256 amount) public {
        // TODO
        token.transferFrom(msg.sender, address(this), amount);
    }
}
