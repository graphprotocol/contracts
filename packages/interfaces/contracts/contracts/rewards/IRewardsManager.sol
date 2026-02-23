// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

import { IIssuanceAllocationDistribution } from "../../issuance/allocate/IIssuanceAllocationDistribution.sol";
import { IRewardsEligibility } from "../../issuance/eligibility/IRewardsEligibility.sol";
import { IRewardsIssuer } from "./IRewardsIssuer.sol";

/**
 * @title IRewardsManager
 * @author Edge & Node
 * @notice Interface for the RewardsManager contract that handles reward distribution
 */
interface IRewardsManager {
    /**
     * @notice Emitted when rewards are assigned to an indexer (Horizon version)
     * @dev We use the Horizon prefix to change the event signature which makes network subgraph development much easier
     * @param indexer Address of the indexer receiving rewards
     * @param allocationID Address of the allocation receiving rewards
     * @param amount Amount of rewards assigned
     */
    event HorizonRewardsAssigned(address indexed indexer, address indexed allocationID, uint256 amount);
    // solhint-disable-previous-line gas-indexed-events

    /**
     * @notice Emitted when rewards are denied to an indexer
     * @param indexer Address of the indexer being denied rewards
     * @param allocationID Address of the allocation being denied rewards
     */
    event RewardsDenied(address indexed indexer, address indexed allocationID);

    /**
     * @notice Emitted when a subgraph is denied for claiming rewards
     * @param subgraphDeploymentID Subgraph deployment ID being denied
     * @param sinceBlock Block number since when the subgraph is denied
     */
    event RewardsDenylistUpdated(bytes32 indexed subgraphDeploymentID, uint256 sinceBlock);
    // solhint-disable-previous-line gas-indexed-events

    /**
     * @notice Emitted when the subgraph service is set
     * @param oldSubgraphService Previous subgraph service address
     * @param newSubgraphService New subgraph service address
     */
    event SubgraphServiceSet(address indexed oldSubgraphService, address indexed newSubgraphService);

    /**
     * @notice Emitted when rewards are denied to an indexer due to eligibility
     * @param indexer Address of the indexer being denied rewards
     * @param allocationID Address of the allocation being denied rewards
     * @param amount Amount of rewards denied
     */
    event RewardsDeniedDueToEligibility(address indexed indexer, address indexed allocationID, uint256 amount);
    // solhint-disable-previous-line gas-indexed-events

    /**
     * @notice Emitted when the rewards eligibility oracle contract is set
     * @param oldRewardsEligibilityOracle Previous rewards eligibility oracle address
     * @param newRewardsEligibilityOracle New rewards eligibility oracle address
     */
    event RewardsEligibilityOracleSet(
        address indexed oldRewardsEligibilityOracle,
        address indexed newRewardsEligibilityOracle
    );

    /**
     * @notice New reclaim address set
     * @param reason The reclaim reason (or condition) identifier (see RewardsCondition library for canonical reasons)
     * @param oldAddress Previous address for this reason
     * @param newAddress New address for this reason
     */
    event ReclaimAddressSet(bytes32 indexed reason, address indexed oldAddress, address indexed newAddress);

    /**
     * @notice Default reclaim address changed
     * @param oldAddress Previous default reclaim address
     * @param newAddress New default reclaim address
     */
    event DefaultReclaimAddressSet(address indexed oldAddress, address indexed newAddress);

    /**
     * @notice Rewards reclaimed to a configured address
     * @param reason The reclaim reason identifier
     * @param amount Amount of rewards reclaimed
     * @param indexer Address of the indexer
     * @param allocationID Address of the allocation
     * @param subgraphDeploymentID Subgraph deployment ID for the allocation
     */
    event RewardsReclaimed(
        bytes32 indexed reason,
        uint256 amount,
        address indexed indexer,
        address indexed allocationID,
        bytes32 subgraphDeploymentID
    );

    /**
     * @dev Accumulated rewards and snapshots for a SubgraphDeployment.
     * See `onSubgraphAllocationUpdate()` for claimability behavior.
     * @param accRewardsForSubgraph Total rewards allocated to this subgraph (always increases)
     * @param accRewardsForSubgraphSnapshot Snapshot for calculating new rewards since last update
     * @param accRewardsPerSignalSnapshot Snapshot of global accRewardsPerSignal at last update
     * @param accRewardsPerAllocatedToken Per-token rewards for allocations (frozen when not claimable)
     */
    struct Subgraph {
        uint256 accRewardsForSubgraph;
        uint256 accRewardsForSubgraphSnapshot;
        uint256 accRewardsPerSignalSnapshot;
        uint256 accRewardsPerAllocatedToken;
    }

    // -- Config --

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
     * @param reason The reclaim reason identifier (see RewardsCondition library for canonical reasons)
     * @param newReclaimAddress The address to receive tokens
     */
    function setReclaimAddress(bytes32 reason, address newReclaimAddress) external;

    /**
     * @notice Set the default reclaim address used when no reason-specific address is configured
     * @dev This is the fallback address used after trying all applicable reason-specific addresses.
     * Set to zero to disable (rewards will be dropped if no specific address matches).
     * @param newDefaultReclaimAddress The fallback address for reclaims
     */
    function setDefaultReclaimAddress(address newDefaultReclaimAddress) external;

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
     * @notice Get the subgraph service address
     * @return The subgraph service contract
     */
    function subgraphService() external view returns (IRewardsIssuer);

    /**
     * @notice Get the issuance allocator address
     * @dev When set, this allocator controls issuance distribution instead of issuancePerBlock
     * @return The issuance allocator contract (zero address if not set)
     */
    function getIssuanceAllocator() external view returns (IIssuanceAllocationDistribution);

    /**
     * @notice Get the reclaim address for a specific reason
     * @param reason The reclaim reason identifier
     * @return The address that receives reclaimed tokens for this reason (zero address if not set)
     */
    function getReclaimAddress(bytes32 reason) external view returns (address);

    /**
     * @notice Get the default reclaim address
     * @return The fallback address for reclaims when no reason-specific address is configured
     */
    function getDefaultReclaimAddress() external view returns (address);

    /**
     * @notice Get the rewards eligibility oracle address
     * @return The rewards eligibility oracle contract
     */
    function getRewardsEligibilityOracle() external view returns (IRewardsEligibility);

    /**
     * @notice Gets the effective issuance per block, accounting for the issuance allocator
     * @dev When an issuance allocator is set, returns the allocated rate for this contract.
     * Otherwise falls back to the raw storage value.
     * @return The effective issuance per block
     */
    function getAllocatedIssuancePerBlock() external view returns (uint256);

    /**
     * @notice Gets the raw issuance per block value from contract storage
     * @dev This returns the storage value directly, ignoring the issuance allocator.
     * Prefer {getAllocatedIssuancePerBlock} for the effective protocol rate.
     * @return The raw issuance per block from storage
     */
    function getRawIssuancePerBlock() external view returns (uint256);

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
     * @param reason The reclaim reason identifier (see RewardsCondition library for canonical reasons)
     * @param allocationID Allocation
     * @return The amount of rewards that were reclaimed (0 if no reclaim address set)
     */
    function reclaimRewards(bytes32 reason, address allocationID) external returns (uint256);

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
     *
     * ## Non-Claimable Behavior
     *
     * When the subgraph is not claimable (denied or below minimum signal):
     * - `accRewardsForSubgraph` increases (rewards continue accruing to the subgraph)
     * - `accRewardsPerAllocatedToken` does NOT increase (rewards not distributed to allocations)
     * - Accrued rewards are reclaimed (if reclaim address configured)
     * - All snapshots update to track the reclaimed amounts
     *
     * @param subgraphDeploymentID Subgraph deployment
     * @return Accumulated rewards per allocated token for a subgraph
     */
    function onSubgraphAllocationUpdate(bytes32 subgraphDeploymentID) external returns (uint256);
}
