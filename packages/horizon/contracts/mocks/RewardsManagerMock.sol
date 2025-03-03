// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { MockGRTToken } from "./MockGRTToken.sol";

contract RewardsManagerMock {
    // -- Variables --
    MockGRTToken public token;
    uint256 private rewards;

    // -- Constructor --

    constructor(MockGRTToken _token, uint256 _rewards) {
        token = _token;
        rewards = _rewards;
    }

    function takeRewards(address) external returns (uint256) {
        token.mint(msg.sender, rewards);
        return rewards;
    }

    function onSubgraphAllocationUpdate(bytes32) public returns (uint256) {}
    function onSubgraphSignalUpdate(bytes32 _subgraphDeploymentID) external returns (uint256) {}
}
