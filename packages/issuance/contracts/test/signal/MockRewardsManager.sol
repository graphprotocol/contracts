// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.27;

/**
 * @title MockRewardsManager
 * @author Edge & Node
 * @notice Minimal mock for testing IndexingSignal.
 * Only implements the methods IndexingSignal actually calls.
 */
contract MockRewardsManager {
    /// @notice The issuance rate per block used for testing
    uint256 public allocatedIssuancePerBlock;
    /// @notice Number of times onSubgraphSignalUpdate has been called
    uint256 public signalUpdateCallCount;
    /// @notice The subgraph deployment ID from the last signal update call
    bytes32 public lastSignalUpdateSubgraph;

    /// @notice Set the allocated issuance per block for testing
    /// @param _issuancePerBlock The issuance rate to set
    function setAllocatedIssuancePerBlock(uint256 _issuancePerBlock) external {
        allocatedIssuancePerBlock = _issuancePerBlock;
    }

    /// @notice Get the allocated issuance per block
    /// @return The current issuance rate per block
    function getAllocatedIssuancePerBlock() external view returns (uint256) {
        return allocatedIssuancePerBlock;
    }

    /// @notice Called when subgraph signal is updated
    /// @param subgraphDeploymentID The subgraph deployment that was updated
    /// @return Always returns 0
    function onSubgraphSignalUpdate(bytes32 subgraphDeploymentID) external returns (uint256) {
        ++signalUpdateCallCount;
        lastSignalUpdateSubgraph = subgraphDeploymentID;
        return 0;
    }
}
