// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

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

    /// @notice Payment cut definitions for each payment type
    struct PaymentCuts {
        // The cut the service provider takes from the payment
        uint128 serviceCut;
        // The cut curators take from the payment
        uint128 curationCut;
    }

    /**
     * @notice Emitted when a subgraph service collects query fees from Graph Payments
     * @param serviceProvider The address of the service provider
     * @param tokensCollected The amount of tokens collected
     * @param tokensCurators The amount of tokens curators receive
     * @param tokensSubgraphService The amount of tokens the subgraph service receives
     */
    event QueryFeesCollected(
        address indexed serviceProvider,
        uint256 tokensCollected,
        uint256 tokensCurators,
        uint256 tokensSubgraphService
    );

    /**
     * @notice Emitted when the stake to fees ratio is set.
     * @param ratio The stake to fees ratio
     */
    event StakeToFeesRatioSet(uint256 ratio);

    /**
     * @notice Emmited when payment cuts are set for a payment type
     * @param paymentType The payment type
     * @param serviceCut The service cut for the payment type
     * @param curationCut The curation cut for the payment type
     */
    event PaymentCutsSet(IGraphPayments.PaymentTypes paymentType, uint128 serviceCut, uint128 curationCut);

    /**
     * @notice Thrown when an indexer tries to register with an empty URL
     */
    error SubgraphServiceEmptyUrl();

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
     * @param tokensCollected The amount of tokens collected
     */
    error SubgraphServiceInconsistentCollection(uint256 balanceBefore, uint256 balanceAfter, uint256 tokensCollected);

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
     * @notice Initialize the contract
     * @param minimumProvisionTokens The minimum amount of provisioned tokens required to create an allocation
     * @param maximumDelegationRatio The maximum delegation ratio allowed for an allocation
     */
    function initialize(uint256 minimumProvisionTokens, uint32 maximumDelegationRatio) external;

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
     * @notice Sets the payment cuts for a payment type
     * @dev Emits a {PaymentCutsSet} event
     * @param paymentType The payment type
     * @param serviceCut The service cut for the payment type
     * @param curationCut The curation cut for the payment type
     */
    function setPaymentCuts(IGraphPayments.PaymentTypes paymentType, uint128 serviceCut, uint128 curationCut) external;

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
}
