// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IDataServiceFees } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataServiceFees.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";

import { Allocation } from "../libraries/Allocation.sol";
import { LegacyAllocation } from "../libraries/LegacyAllocation.sol";

/**
 * @title Interface for the {SubgraphService} contract
 * @dev This interface extends {IDataServiceFees} and {IDataService}.
 * @notice The Subgraph Service is a data service built on top of Graph Horizon that supports the use case of
 * subgraph indexing and querying. The {SubgraphService} contract implements the flows described in the Data
 * Service framework to allow indexers to register as subgraph service providers, create allocations to signal
 * their commitment to index a subgraph, and collect fees for indexing and querying services.
 */
interface ISubgraphService is IDataServiceFees {
    /// @notice Contains details for each indexer
    struct Indexer {
        // Timestamp when the indexer registered
        uint256 registeredAt;
        // The URL where the indexer can be reached at for queries
        string url;
        // The indexer's geo location, expressed as a geo hash
        string geoHash;
    }

    /**
     * @notice Emitted when a subgraph service collects query fees from Graph Payments
     * @param serviceProvider The address of the service provider
     * @param tokensCollected The amount of tokens collected
     * @param tokensCurators The amount of tokens curators receive
     */
    event QueryFeesCollected(address indexed serviceProvider, uint256 tokensCollected, uint256 tokensCurators);

    /**
     * @notice Emitted when the stake to fees ratio is set.
     * @param ratio The stake to fees ratio
     */
    event StakeToFeesRatioSet(uint256 ratio);

    /**
     * @notice Emitted when curator cuts are set
     * @param curationCut The curation cut
     */
    event CurationCutSet(uint256 curationCut);

    /**
     * Thrown when trying to set a curation cut that is not a valid PPM value
     * @param curationCut The curation cut value
     */
    error SubgraphServiceInvalidCurationCut(uint256 curationCut);

    /**
     * @notice Thrown when an indexer tries to register with an empty URL
     */
    error SubgraphServiceEmptyUrl();

    /**
     * @notice Thrown when an indexer tries to register with an empty geohash
     */
    error SubgraphServiceEmptyGeohash();

    /**
     * @notice Thrown when an indexer tries to register but they are already registered
     */
    error SubgraphServiceIndexerAlreadyRegistered();

    /**
     * @notice Thrown when an indexer tries to perform an operation but they are not registered
     * @param indexer The address of the indexer that is not registered
     */
    error SubgraphServiceIndexerNotRegistered(address indexer);

    /**
     * @notice Thrown when an indexer tries to collect fees for an unsupported payment type
     * @param paymentType The payment type that is not supported
     */
    error SubgraphServiceInvalidPaymentType(IGraphPayments.PaymentTypes paymentType);

    /**
     * @notice Thrown when the contract GRT balance is inconsistent with the payment amount collected
     * from Graph Payments
     * @param balanceBefore The contract GRT balance before the collection
     * @param balanceAfter The contract GRT balance after the collection
     * @param tokensDataService The amount of tokens sent to the subgraph service
     */
    error SubgraphServiceInconsistentCollection(uint256 balanceBefore, uint256 balanceAfter, uint256 tokensDataService);

    /**
     * @notice @notice Thrown when the service provider in the RAV does not match the expected indexer.
     * @param providedIndexer The address of the provided indexer.
     * @param expectedIndexer The address of the expected indexer.
     */
    error SubgraphServiceIndexerMismatch(address providedIndexer, address expectedIndexer);

    /**
     * @notice Thrown when the indexer in the allocation state does not match the expected indexer.
     * @param indexer The address of the expected indexer.
     * @param allocationId The id of the allocation.
     */
    error SubgraphServiceAllocationNotAuthorized(address indexer, address allocationId);

    /**
     * @notice Thrown when collecting a RAV where the RAV indexer is not the same as the allocation indexer
     * @param ravIndexer The address of the RAV indexer
     * @param allocationIndexer The address of the allocation indexer
     */
    error SubgraphServiceInvalidRAV(address ravIndexer, address allocationIndexer);

    /**
     * @notice Thrown when trying to force close an allocation that is not stale
     * @param allocationId The id of the allocation
     */
    error SubgraphServiceCannotForceCloseAllocation(address allocationId);

    /**
     * @notice Thrown when trying to force close an altruistic allocation
     * @param allocationId The id of the allocation
     */
    error SubgraphServiceAllocationIsAltruistic(address allocationId);

    /**
     * @notice Thrown when trying to force close an allocation that is not over-allocated
     * @param allocationId The id of the allocation
     */
    error SubgraphServiceAllocationNotOverAllocated(address allocationId);

    /**
     * @notice Thrown when trying to set stake to fees ratio to zero
     */
    error SubgraphServiceInvalidZeroStakeToFeesRatio();

    /**
     * @notice Force close an allocation
     * @dev This function can be permissionlessly called when the allocation is stale or
     * if the indexer is over-allocated. This ensures that rewards for other allocations are
     * not diluted by an inactive allocation, and that over-allocated indexers stop accumulating
     * rewards with tokens they no longer have allocated.
     *
     * Requirements:
     * - Allocation must exist and be open
     * - Allocation must be stale or indexer must be over-allocated
     * - Allocation cannot be altruistic
     *
     * Emits a {AllocationClosed} event.
     *
     * @param allocationId The id of the allocation
     */
    function forceCloseAllocation(address allocationId) external;

    /**
     * @notice Change the amount of tokens in an allocation
     * @dev Requirements:
     * - The indexer must be registered
     * - The provision must be valid according to the subgraph service rules
     * - `tokens` must be different from the current allocation size
     * - The indexer must have enough available tokens to allocate if they are upsizing the allocation
     *
     * Emits a {AllocationResized} event.
     *
     * See {AllocationManager-_resizeAllocation} for more details.
     *
     * @param indexer The address of the indexer
     * @param allocationId The id of the allocation
     * @param tokens The new amount of tokens in the allocation
     */
    function resizeAllocation(address indexer, address allocationId, uint256 tokens) external;

    /**
     * @notice Imports a legacy allocation id into the subgraph service
     * This is a governor only action that is required to prevent indexers from re-using allocation ids from the
     * legacy staking contract.
     * @param indexer The address of the indexer
     * @param allocationId The id of the allocation
     * @param subgraphDeploymentId The id of the subgraph deployment
     */
    function migrateLegacyAllocation(address indexer, address allocationId, bytes32 subgraphDeploymentId) external;

    /**
     * @notice Sets a pause guardian
     * @param pauseGuardian The address of the pause guardian
     * @param allowed True if the pause guardian is allowed to pause the contract, false otherwise
     */
    function setPauseGuardian(address pauseGuardian, bool allowed) external;

    /**
     * @notice Sets the minimum amount of provisioned tokens required to create an allocation
     * @param minimumProvisionTokens The minimum amount of provisioned tokens required to create an allocation
     */
    function setMinimumProvisionTokens(uint256 minimumProvisionTokens) external;

    /**
     * @notice Sets the delegation ratio
     * @param delegationRatio The delegation ratio
     */
    function setDelegationRatio(uint32 delegationRatio) external;

    /**
     * @notice Sets the stake to fees ratio
     * @param stakeToFeesRatio The stake to fees ratio
     */
    function setStakeToFeesRatio(uint256 stakeToFeesRatio) external;

    /**
     * @notice Sets the max POI staleness
     * See {AllocationManagerV1Storage-maxPOIStaleness} for more details.
     * @param maxPOIStaleness The max POI staleness in seconds
     */
    function setMaxPOIStaleness(uint256 maxPOIStaleness) external;

    /**
     * @notice Sets the curators payment cut for query fees
     * @dev Emits a {CuratorCutSet} event
     * @param curationCut The curation cut for the payment type
     */
    function setCurationCut(uint256 curationCut) external;

    /**
     * @notice Sets the rewards destination for an indexer to receive indexing rewards
     * @dev Emits a {RewardsDestinationSet} event
     * @param rewardsDestination The address where indexing rewards should be sent
     */
    function setRewardsDestination(address rewardsDestination) external;

    /**
     * @notice Gets the details of an allocation
     * For legacy allocations use {getLegacyAllocation}
     * @param allocationId The id of the allocation
     */
    function getAllocation(address allocationId) external view returns (Allocation.State memory);

    /**
     * @notice Gets the details of a legacy allocation
     * For non-legacy allocations use {getAllocation}
     * @param allocationId The id of the allocation
     */
    function getLegacyAllocation(address allocationId) external view returns (LegacyAllocation.State memory);

    /**
     * @notice Encodes the allocation proof for EIP712 signing
     * @param indexer The address of the indexer
     * @param allocationId The id of the allocation
     */
    function encodeAllocationProof(address indexer, address allocationId) external view returns (bytes32);

    /**
     * @notice Checks if an allocation is stale
     * @param allocationId The id of the allocation
     * @return True if the allocation is stale, false otherwise
     */
    function isStaleAllocation(address allocationId) external view returns (bool);

    /**
     * @notice Checks if an indexer is over-allocated
     * @param allocationId The id of the allocation
     * @return True if the indexer is over-allocated, false otherwise
     */
    function isOverAllocated(address allocationId) external view returns (bool);
}
