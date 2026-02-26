// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { IDataServiceFees } from "../data-service/IDataServiceFees.sol";
import { IGraphPayments } from "../horizon/IGraphPayments.sol";
import { IRecurringCollector } from "../horizon/IRecurringCollector.sol";

import { IAllocation } from "./internal/IAllocation.sol";
import { IIndexingAgreement } from "./internal/IIndexingAgreement.sol";
import { ILegacyAllocation } from "./internal/ILegacyAllocation.sol";

/**
 * @title Interface for the {SubgraphService} contract
 * @author Edge & Node
 * @dev This interface extends {IDataServiceFees} and {IDataService}.
 * @notice The Subgraph Service is a data service built on top of Graph Horizon that supports the use case of
 * subgraph indexing and querying. The {SubgraphService} contract implements the flows described in the Data
 * Service framework to allow indexers to register as subgraph service providers, create allocations to signal
 * their commitment to index a subgraph, and collect fees for indexing and querying services.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface ISubgraphService is IDataServiceFees {
    /**
     * @notice Indexer details
     * @param url The URL where the indexer can be reached at for queries
     * @param geoHash The indexer's geo location, expressed as a geo hash
     */
    struct Indexer {
        string url;
        string geoHash;
    }

    /**
     * @notice Emitted when a subgraph service collects query fees from Graph Payments
     * @param serviceProvider The address of the service provider
     * @param payer The address paying for the query fees
     * @param allocationId The id of the allocation
     * @param subgraphDeploymentId The id of the subgraph deployment
     * @param tokensCollected The amount of tokens collected
     * @param tokensCurators The amount of tokens curators receive
     */
    event QueryFeesCollected(
        address indexed serviceProvider,
        address indexed payer,
        address indexed allocationId,
        bytes32 subgraphDeploymentId,
        uint256 tokensCollected,
        uint256 tokensCurators
    );

    /**
     * @notice Emitted when an indexer sets a new payments destination
     * @param indexer The address of the indexer
     * @param paymentsDestination The address where payments should be sent
     */
    event PaymentsDestinationSet(address indexed indexer, address indexed paymentsDestination);

    /**
     * @notice Emitted when the stake to fees ratio is set.
     * @param ratio The stake to fees ratio
     */
    event StakeToFeesRatioSet(uint256 ratio);
    // solhint-disable-previous-line gas-indexed-events

    /**
     * @notice Emitted when curator cuts are set
     * @param curationCut The curation cut
     */
    event CurationCutSet(uint256 curationCut);
    // solhint-disable-previous-line gas-indexed-events

    /**
     * @notice Emitted when indexing fees cut is set
     * @param indexingFeesCut The indexing fees cut
     */
    event IndexingFeesCutSet(uint256 indexingFeesCut);
    // solhint-disable-previous-line gas-indexed-events

    /**
     * @notice Thrown when trying to set a curation cut that is not a valid PPM value
     * @param curationCut The curation cut value
     */
    error SubgraphServiceInvalidCurationCut(uint256 curationCut);

    /**
     * @notice Thrown when trying to set an indexing fees cut that is not a valid PPM value
     * @param indexingFeesCut The indexing fees cut value
     */
    error SubgraphServiceInvalidIndexingFeesCut(uint256 indexingFeesCut);

    /**
     * @notice Thrown when an indexer tries to register with an empty URL
     */
    error SubgraphServiceEmptyUrl();

    /**
     * @notice Thrown when an indexer tries to register with an empty geohash
     */
    error SubgraphServiceEmptyGeohash();

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
     * @notice Thrown when the contract GRT balance is inconsistent after collecting from Graph Payments
     * @param balanceBefore The contract GRT balance before the collection
     * @param balanceAfter The contract GRT balance after the collection
     */
    error SubgraphServiceInconsistentCollection(uint256 balanceBefore, uint256 balanceAfter);

    /**
     * @notice @notice Thrown when the service provider does not match the expected indexer.
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
     * @notice Thrown when trying to force close an allocation that is not stale and the indexer is not over-allocated
     * @param allocationId The id of the allocation
     */
    error SubgraphServiceCannotForceCloseAllocation(address allocationId);

    /**
     * @notice Thrown when trying to force close an altruistic allocation
     * @param allocationId The id of the allocation
     */
    error SubgraphServiceAllocationIsAltruistic(address allocationId);

    /**
     * @notice Thrown when trying to set stake to fees ratio to zero
     */
    error SubgraphServiceInvalidZeroStakeToFeesRatio();

    /**
     * @notice Thrown when collectionId is not a valid address
     * @param collectionId The collectionId
     */
    error SubgraphServiceInvalidCollectionId(bytes32 collectionId);

    /**
     * @notice Initialize the contract
     * @dev The thawingPeriod and verifierCut ranges are not set here because they are variables
     * on the DisputeManager. We use the {ProvisionManager} overrideable getters to get the ranges.
     * @param owner The owner of the contract
     * @param minimumProvisionTokens The minimum amount of provisioned tokens required to create an allocation
     * @param maximumDelegationRatio The maximum delegation ratio allowed for an allocation
     * @param stakeToFeesRatio The ratio of stake to fees to lock when collecting query fees
     */
    function initialize(
        address owner,
        uint256 minimumProvisionTokens,
        uint32 maximumDelegationRatio,
        uint256 stakeToFeesRatio
    ) external;

    /**
     * @notice Force close a stale allocation
     * @dev This function can be permissionlessly called when the allocation is stale. This
     * ensures that rewards for other allocations are not diluted by an inactive allocation.
     *
     * Requirements:
     * - Allocation must exist and be open
     * - Allocation must be stale
     * - Allocation cannot be altruistic
     *
     * Emits a {AllocationClosed} event.
     *
     * @param allocationId The id of the allocation
     */
    function closeStaleAllocation(address allocationId) external;

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
     * @param newStakeToFeesRatio The stake to fees ratio
     */
    function setStakeToFeesRatio(uint256 newStakeToFeesRatio) external;

    /**
     * @notice Sets the max POI staleness
     * See {AllocationManagerV1Storage-maxPOIStaleness} for more details.
     * @param newMaxPoiStaleness The max POI staleness in seconds
     */
    function setMaxPOIStaleness(uint256 newMaxPoiStaleness) external;

    /**
     * @notice Sets the curators payment cut for query fees
     * @dev Emits a {CuratorCutSet} event
     * @param curationCut The curation cut for the payment type
     */
    function setCurationCut(uint256 curationCut) external;

    /**
     * @notice Sets the data service payment cut for indexing fees
     * @dev Emits a {IndexingFeesCutSet} event
     * @param indexingFeesCut The indexing fees cut for the payment type
     */
    function setIndexingFeesCut(uint256 indexingFeesCut) external;

    /**
     * @notice Sets the payments destination for an indexer to receive payments
     * @dev Emits a {PaymentsDestinationSet} event
     * @param newPaymentsDestination The address where payments should be sent
     */
    function setPaymentsDestination(address newPaymentsDestination) external;

    /**
     * @notice Accept an indexing agreement.
     * @param allocationId The id of the allocation
     * @param signedRCA The signed recurring collector agreement (RCA) that the indexer accepts
     * @return agreementId The ID of the accepted indexing agreement
     */
    function acceptIndexingAgreement(
        address allocationId,
        IRecurringCollector.SignedRCA calldata signedRCA
    ) external returns (bytes16);

    /**
     * @notice Update an indexing agreement.
     * @param indexer The address of the indexer
     * @param signedRCAU The signed recurring collector agreement update (RCAU) that the indexer accepts
     */
    function updateIndexingAgreement(address indexer, IRecurringCollector.SignedRCAU calldata signedRCAU) external;

    /**
     * @notice Cancel an indexing agreement by indexer / operator.
     * @param indexer The address of the indexer
     * @param agreementId The id of the indexing agreement
     */
    function cancelIndexingAgreement(address indexer, bytes16 agreementId) external;

    /**
     * @notice Cancel an indexing agreement by payer / signer.
     * @param agreementId The id of the indexing agreement
     */
    function cancelIndexingAgreementByPayer(bytes16 agreementId) external;

    /**
     * @notice Get the indexing agreement for a given agreement ID.
     * @param agreementId The id of the indexing agreement
     * @return The indexing agreement details
     */
    function getIndexingAgreement(
        bytes16 agreementId
    ) external view returns (IIndexingAgreement.AgreementWrapper memory);

    /**
     * @notice Gets the details of an allocation
     * For legacy allocations use {getLegacyAllocation}
     * @param allocationId The id of the allocation
     * @return The allocation details
     */
    function getAllocation(address allocationId) external view returns (IAllocation.State memory);

    /**
     * @notice Gets the details of a legacy allocation
     * For non-legacy allocations use {getAllocation}
     * @param allocationId The id of the allocation
     * @return The legacy allocation details
     */
    function getLegacyAllocation(address allocationId) external view returns (ILegacyAllocation.State memory);

    /**
     * @notice Encodes the allocation proof for EIP712 signing
     * @param indexer The address of the indexer
     * @param allocationId The id of the allocation
     * @return The encoded allocation proof
     */
    function encodeAllocationProof(address indexer, address allocationId) external view returns (bytes32);

    /**
     * @notice Checks if an indexer is over-allocated
     * @param allocationId The id of the allocation
     * @return True if the indexer is over-allocated, false otherwise
     */
    function isOverAllocated(address allocationId) external view returns (bool);

    /**
     * @notice Gets the address of the dispute manager
     * @return The address of the dispute manager
     */
    function getDisputeManager() external view returns (address);

    /**
     * @notice Gets the address of the graph tally collector
     * @return The address of the graph tally collector
     */
    function getGraphTallyCollector() external view returns (address);

    /**
     * @notice Gets the address of the curation contract
     * @return The address of the curation contract
     */
    function getCuration() external view returns (address);

    /**
     * @notice Gets the indexer details
     * @dev Note that this storage getter actually returns a {Indexer} struct, but ethers v6 is not
     *      good at dealing with dynamic types on return values.
     * @param indexer The address of the indexer
     * @return url The URL where the indexer can be reached at for queries
     * @return geoHash The indexer's geo location, expressed as a geo hash
     */
    function indexers(address indexer) external view returns (string memory url, string memory geoHash);

    /**
     * @notice Gets the stake to fees ratio
     * @return The stake to fees ratio
     */
    function stakeToFeesRatio() external view returns (uint256);

    /**
     * @notice Gets the curation fees cut
     * @return The curation fees cut
     */
    function curationFeesCut() external view returns (uint256);

    /**
     * @notice Gets the payments destination
     * @param indexer The address of the indexer
     * @return The payments destination
     */
    function paymentsDestination(address indexer) external view returns (address);
}
