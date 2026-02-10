// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.33;

/**
 * @title MockRewardsManager
 * @notice Minimal mock for testing IndexingSignal.
 * Only implements the methods IndexingSignal actually calls.
 */
contract MockRewardsManager {
    uint256 public allocatedIssuancePerBlock;
    uint256 public signalUpdateCallCount;
    bytes32 public lastSignalUpdateSubgraph;

    function setAllocatedIssuancePerBlock(uint256 _issuancePerBlock) external {
        allocatedIssuancePerBlock = _issuancePerBlock;
    }

    function getAllocatedIssuancePerBlock() external view returns (uint256) {
        return allocatedIssuancePerBlock;
    }

    function onSubgraphSignalUpdate(bytes32 subgraphDeploymentID) external returns (uint256) {
        signalUpdateCallCount++;
        lastSignalUpdateSubgraph = subgraphDeploymentID;
        return 0;
    }
}
