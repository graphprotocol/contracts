// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.27;

import { MockGRTToken } from "./MockGRTToken.sol";

/**
 * @title RewardsManagerMock
 * @author Edge & Node
 * @notice Mock implementation of the RewardsManager for testing
 */
contract RewardsManagerMock {
    // -- Variables --
    /// @notice The mock GRT token contract
    MockGRTToken public token;
    uint256 private _rewards;

    // -- Constructor --

    /**
     * @notice Constructor for the RewardsManager mock
     * @param token_ The mock GRT token contract
     * @param rewards The amount of rewards to distribute
     */
    constructor(MockGRTToken token_, uint256 rewards) {
        token = token_;
        _rewards = rewards;
    }

    /**
     * @notice Take rewards for an allocation
     * @param allocationId The allocation ID (unused in this mock)
     * @return The amount of rewards taken
     */
    function takeRewards(address allocationId) external returns (uint256) {
        allocationId; // silence unused variable warning
        token.mint(msg.sender, _rewards);
        return _rewards;
    }

    /**
     * @notice Handle subgraph allocation update (mock implementation)
     * @param subgraphDeploymentId The subgraph deployment ID (unused in this mock)
     * @return Always returns 0 in mock
     */
    function onSubgraphAllocationUpdate(bytes32 subgraphDeploymentId) public pure returns (uint256) {
        subgraphDeploymentId; // silence unused variable warning
        return 0;
    }

    /**
     * @notice Handle subgraph signal update (mock implementation)
     * @param subgraphDeploymentId The subgraph deployment ID (unused in this mock)
     * @return Always returns 0 in mock
     */
    function onSubgraphSignalUpdate(bytes32 subgraphDeploymentId) external pure returns (uint256) {
        subgraphDeploymentId; // silence unused variable warning
        return 0;
    }
}
