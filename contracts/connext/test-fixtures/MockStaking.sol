pragma solidity ^0.6.4;

import "../../IGraphToken.sol";

import "../MinimumViableMultisig.sol";

contract MockStaking {
    IGraphToken public token;

    event CollectCalled(uint256 amount, address channelID, address sender);

    constructor(IGraphToken _token) public {
        token = _token;
    }

    mapping(address => address) channelIDToChannelProxy;

    function isChannel(address channelID) public view returns (bool) {
        return channelIDToChannelProxy[channelID] != address(0);
    }

    function setChannel(address channelID, address channelProxy) public {
        require(
            channelID != address(0),
            "MockStaking: channelID must not be zero"
        );
        require(
            channelProxy != address(0),
            "MockStaking: channelProxy must not be zero"
        );

        channelIDToChannelProxy[channelID] = channelProxy;
    }

    function collect(uint256 amount, address channelID) public {
        require(
            channelID != address(0),
            "MockStaking: invalid channelID"
        );
        require(
            channelIDToChannelProxy[channelID] == msg.sender,
            "MockStaking: mismatch between channelID and caller"
        );

        require(
            token.transferFrom(msg.sender, address(this), amount),
            "MockStaking: token transfer failed"
        );

        emit CollectCalled(amount, channelID, msg.sender);
    }

    function lockMultisig(MinimumViableMultisig multisig) public {
        multisig.lock();
    }
}
