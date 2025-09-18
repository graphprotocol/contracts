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
     * @param _issuancePerBlock The amount of tokens to issue per block
     */
    function setIssuancePerBlock(uint256 _issuancePerBlock) external;

    /**
     * @notice Sets the minimum signaled tokens on a subgraph to start accruing rewards
     * @dev Can be set to zero which means that this feature is not being used
     * @param _minimumSubgraphSignal Minimum signaled tokens
     */
    function setMinimumSubgraphSignal(uint256 _minimumSubgraphSignal) external;

    /**
     * @notice Set the subgraph service address
     * @param _subgraphService Address of the subgraph service contract
     */
    function setSubgraphService(address _subgraphService) external;

    /**
     * @notice Set the rewards eligibility oracle address
     * @param newRewardsEligibilityOracle The address of the rewards eligibility oracle
     */
    function setRewardsEligibilityOracle(address newRewardsEligibilityOracle) external;

    // -- Denylist --

    /**
     * @notice Set the subgraph availability oracle address
     * @param _subgraphAvailabilityOracle The address of the subgraph availability oracle
     */
    function setSubgraphAvailabilityOracle(address _subgraphAvailabilityOracle) external;

    /**
     * @notice Set the denied status for a subgraph deployment
     * @param _subgraphDeploymentID The subgraph deployment ID
     * @param _deny True to deny, false to allow
     */
    function setDenied(bytes32 _subgraphDeploymentID, bool _deny) external;

    /**
     * @notice Check if a subgraph deployment is denied
     * @param _subgraphDeploymentID The subgraph deployment ID to check
     * @return True if the subgraph is denied, false otherwise
     */
    function isDenied(bytes32 _subgraphDeploymentID) external view returns (bool);

    // -- Getters --

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
     * @param _subgraphDeploymentID The subgraph deployment ID
     * @return The accumulated rewards for the subgraph
     */
    function getAccRewardsForSubgraph(bytes32 _subgraphDeploymentID) external view returns (uint256);

    /**
     * @notice Gets the accumulated rewards per allocated token for the subgraph
     * @param _subgraphDeploymentID Subgraph deployment
     * @return Accumulated rewards per allocated token for the subgraph
     * @return Accumulated rewards for subgraph
     */
    function getAccRewardsPerAllocatedToken(bytes32 _subgraphDeploymentID) external view returns (uint256, uint256);

    /**
     * @notice Calculate current rewards for a given allocation on demand
     * @param _allocationID Allocation
     * @return Rewards amount for an allocation
     */
    function getRewards(address _rewardsIssuer, address _allocationID) external view returns (uint256);

    function calcRewards(uint256 _tokens, uint256 _accRewardsPerAllocatedToken) external pure returns (uint256);

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
     * @param _allocationID Allocation
     * @return Assigned rewards amount
     */
    function takeRewards(address _allocationID) external returns (uint256);

    // -- Hooks --

    /**
     * @notice Triggers an update of rewards for a subgraph
     * @dev Must be called before `signalled GRT` on a subgraph changes.
     * Hook called from the Curation contract on mint() and burn()
     * @param _subgraphDeploymentID Subgraph deployment
     * @return Accumulated rewards for subgraph
     */
    function onSubgraphSignalUpdate(bytes32 _subgraphDeploymentID) external returns (uint256);

    /**
     * @notice Triggers an update of rewards for a subgraph
     * @dev Must be called before allocation on a subgraph changes.
     * Hook called from the Staking contract on allocate() and close()
     * @param _subgraphDeploymentID Subgraph deployment
     * @return Accumulated rewards per allocated token for a subgraph
     */
    function onSubgraphAllocationUpdate(bytes32 _subgraphDeploymentID) external returns (uint256);
}
