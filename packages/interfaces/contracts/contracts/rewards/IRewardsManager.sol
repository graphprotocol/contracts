// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title IRewardsManager
 * @author Edge & Node
 * @notice Interface for the RewardsManager contract that handles reward distribution
 */
interface IRewardsManager {
    /**
     * @dev Stores accumulated rewards and snapshots related to a particular SubgraphDeployment
     * @param accRewardsForSubgraph Accumulated rewards for the subgraph
     * @param accRewardsForSubgraphSnapshot Snapshot of accumulated rewards for the subgraph
     * @param accRewardsPerSignalSnapshot Snapshot of accumulated rewards per signal
     * @param accRewardsPerAllocatedToken Accumulated rewards per allocated token
     */
    struct Subgraph {
        uint256 accRewardsForSubgraph;
        uint256 accRewardsForSubgraphSnapshot;
        uint256 accRewardsPerSignalSnapshot;
        uint256 accRewardsPerAllocatedToken;
    }

    // -- Config --

    /**
     * @notice Set the issuance per block for rewards distribution
     * @param issuancePerBlock The amount of tokens to issue per block
     */
    function setIssuancePerBlock(uint256 issuancePerBlock) external;

    /**
     * @notice Sets the minimum signaled tokens on a subgraph to start accruing rewards
     * @dev Can be set to zero which means that this feature is not being used
     * @param minimumSubgraphSignal Minimum signaled tokens
     */
    function setMinimumSubgraphSignal(uint256 minimumSubgraphSignal) external;

    /**
     * @notice Set the subgraph service address
     * @param newSubgraphService Address of the subgraph service contract
     */
    function setSubgraphService(address newSubgraphService) external;

    /**
     * @notice Set the rewards eligibility oracle address
     * @param newRewardsEligibilityOracle The address of the rewards eligibility oracle
     */
    function setRewardsEligibilityOracle(address newRewardsEligibilityOracle) external;

    /**
     * @notice Set the reclaim address for a specific reason
     * @dev Address to mint tokens for denied/reclaimed rewards. Set to zero to disable.
     *
     * IMPORTANT: Changes take effect immediately and retroactively. All unclaimed rewards from
     * previous periods will be sent to the new reclaim address when they are eventually reclaimed,
     * regardless of which address was configured when the rewards were originally accrued.
     *
     * @param reason The reclaim reason identifier (see RewardsReclaim library for canonical reasons)
     * @param newReclaimAddress The address to receive tokens
     */
    function setReclaimAddress(bytes32 reason, address newReclaimAddress) external;

    // -- Denylist --

    /**
     * @notice Set the subgraph availability oracle address
     * @param subgraphAvailabilityOracle The address of the subgraph availability oracle
     */
    function setSubgraphAvailabilityOracle(address subgraphAvailabilityOracle) external;

    /**
     * @notice Set the denied status for a subgraph deployment
     * @param subgraphDeploymentID The subgraph deployment ID
     * @param deny True to deny, false to allow
     */
    function setDenied(bytes32 subgraphDeploymentID, bool deny) external;

    /**
     * @notice Check if a subgraph deployment is denied
     * @param subgraphDeploymentID The subgraph deployment ID to check
     * @return True if the subgraph is denied, false otherwise
     */
    function isDenied(bytes32 subgraphDeploymentID) external view returns (bool);

    // -- Getters --

    /**
     * @notice Gets the effective issuance per block for rewards
     * @dev Takes into account the issuance allocator if set
     * @return The effective issuance per block
     */
    function getRewardsIssuancePerBlock() external view returns (uint256);

    /**
     * @notice Gets the issuance of rewards per signal since last updated
     * @return newly accrued rewards per signal since last update
     */
    function getNewRewardsPerSignal() external view returns (uint256);

    /**
     * @notice Gets the currently accumulated rewards per signal
     * @return Currently accumulated rewards per signal
     */
    function getAccRewardsPerSignal() external view returns (uint256);

    /**
     * @notice Get the accumulated rewards for a specific subgraph
     * @param subgraphDeploymentID The subgraph deployment ID
     * @return The accumulated rewards for the subgraph
     */
    function getAccRewardsForSubgraph(bytes32 subgraphDeploymentID) external view returns (uint256);

    /**
     * @notice Gets the accumulated rewards per allocated token for the subgraph
     * @param subgraphDeploymentID Subgraph deployment
     * @return Accumulated rewards per allocated token for the subgraph
     * @return Accumulated rewards for subgraph
     */
    function getAccRewardsPerAllocatedToken(bytes32 subgraphDeploymentID) external view returns (uint256, uint256);

    /**
     * @notice Calculate current rewards for a given allocation on demand
     * @param rewardsIssuer The rewards issuer contract
     * @param allocationID Allocation
     * @return Rewards amount for an allocation
     */
    function getRewards(address rewardsIssuer, address allocationID) external view returns (uint256);

    /**
     * @notice Calculate rewards based on tokens and accumulated rewards per allocated token
     * @param tokens The number of tokens allocated
     * @param accRewardsPerAllocatedToken The accumulated rewards per allocated token
     * @return The calculated rewards amount
     */
    function calcRewards(uint256 tokens, uint256 accRewardsPerAllocatedToken) external pure returns (uint256);

    // -- Updates --

    /**
     * @notice Updates the accumulated rewards per signal and save checkpoint block number
     * @dev Must be called before `issuancePerBlock` or `total signalled GRT` changes.
     * Called from the Curation contract on mint() and burn()
     * @return Accumulated rewards per signal
     */
    function updateAccRewardsPerSignal() external returns (uint256);

    /**
     * @notice Pull rewards from the contract for a particular allocation
     * @dev This function can only be called by the Staking contract.
     * This function will mint the necessary tokens to reward based on the inflation calculation.
     * @param allocationID Allocation
     * @return Assigned rewards amount
     */
    function takeRewards(address allocationID) external returns (uint256);

    /**
     * @notice Reclaim rewards for an allocation
     * @dev This function can only be called by an authorized rewards issuer.
     * Calculates pending rewards and mints them to the configured reclaim address.
     * @param reason The reclaim reason identifier (see RewardsReclaim library for canonical reasons)
     * @param allocationID Allocation
     * @param data Arbitrary data to include in the RewardsReclaimed event for additional context
     * @return The amount of rewards that were reclaimed (0 if no reclaim address set)
     */
    function reclaimRewards(bytes32 reason, address allocationID, bytes calldata data) external returns (uint256);

    // -- Hooks --

    /**
     * @notice Triggers an update of rewards for a subgraph
     * @dev Must be called before `signalled GRT` on a subgraph changes.
     * Hook called from the Curation contract on mint() and burn()
     * @param subgraphDeploymentID Subgraph deployment
     * @return Accumulated rewards for subgraph
     */
    function onSubgraphSignalUpdate(bytes32 subgraphDeploymentID) external returns (uint256);

    /**
     * @notice Triggers an update of rewards for a subgraph
     * @dev Must be called before allocation on a subgraph changes.
     * Hook called from the Staking contract on allocate() and close()
     * @param subgraphDeploymentID Subgraph deployment
     * @return Accumulated rewards per allocated token for a subgraph
     */
    function onSubgraphAllocationUpdate(bytes32 subgraphDeploymentID) external returns (uint256);
}
