// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { MockGRTToken } from "./MockGRTToken.sol";

contract RewardsManagerMock {
    // -- Variables --
    MockGRTToken public token;
    uint256 private _rewards;

    // -- Constructor --

    constructor(MockGRTToken token_, uint256 rewards) {
        token = token_;
        _rewards = rewards;
    }

    function takeRewards(address) external returns (uint256) {
        token.mint(msg.sender, _rewards);
        return _rewards;
    }

    function onSubgraphAllocationUpdate(bytes32) public returns (uint256) {}
    function onSubgraphSignalUpdate(bytes32 subgraphDeploymentID) external returns (uint256) {}
}
