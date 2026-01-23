// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

// TODO: Re-enable and fix issues when publishing a new version
// forge-lint: disable-start(mixed-case-variable)

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
     * @param allocationID The allocation ID (unused in this mock)
     * @return The amount of rewards taken
     */
    function takeRewards(address allocationID) external returns (uint256) {
        allocationID; // silence unused variable warning
        token.mint(msg.sender, _rewards);
        return _rewards;
    }

    /**
     * @notice Handle subgraph allocation update (mock implementation)
     * @param subgraphDeploymentID The subgraph deployment ID (unused in this mock)
     * @return Always returns 0 in mock
     */
    function onSubgraphAllocationUpdate(bytes32 subgraphDeploymentID) public pure returns (uint256) {
        subgraphDeploymentID; // silence unused variable warning
        return 0;
    }

    /**
     * @notice Handle subgraph signal update (mock implementation)
     * @param subgraphDeploymentID The subgraph deployment ID (unused in this mock)
     * @return Always returns 0 in mock
     */
    function onSubgraphSignalUpdate(bytes32 subgraphDeploymentID) external pure returns (uint256) {
        subgraphDeploymentID; // silence unused variable warning
        return 0;
    }
}
