// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.33;

import { ProvisionTracker } from "./ProvisionTracker.sol";
import { IHorizonStaking } from "../../interfaces/IHorizonStaking.sol";
import { LinkedList } from "../../libraries/LinkedList.sol";

library StakeClaims {
    using ProvisionTracker for mapping(address => uint256);
    using LinkedList for LinkedList.List;

    /**
     * @notice A stake claim, representing provisioned stake that gets locked
     * to be released to a service provider.
     * @dev StakeClaims are stored in linked lists by service provider, ordered by
     * creation timestamp.
     * @param tokens The amount of tokens to be locked in the claim
     * @param createdAt The timestamp when the claim was created
     * @param releasableAt The timestamp when the tokens can be released
     * @param nextClaim The next claim in the linked list
     */
    struct StakeClaim {
        uint256 tokens;
        uint256 createdAt;
        uint256 releasableAt;
        bytes32 nextClaim;
    }

    /**
     * @notice Emitted when a stake claim is created and stake is locked.
     * @param serviceProvider The address of the service provider
     * @param claimId The id of the stake claim
     * @param tokens The amount of tokens to lock in the claim
     * @param unlockTimestamp The timestamp when the tokens can be released
     */
    event StakeClaimLocked(
        address indexed serviceProvider,
        bytes32 indexed claimId,
        uint256 tokens,
        uint256 unlockTimestamp
    );

    /**
     * @notice Emitted when a stake claim is released and stake is unlocked.
     * @param serviceProvider The address of the service provider
     * @param claimId The id of the stake claim
     * @param tokens The amount of tokens released
     * @param releasableAt The timestamp when the tokens were released
     */
    event StakeClaimReleased(
        address indexed serviceProvider,
        bytes32 indexed claimId,
        uint256 tokens,
        uint256 releasableAt
    );

    /**
     * @notice Emitted when a series of stake claims are released.
     * @param serviceProvider The address of the service provider
     * @param claimsCount The number of stake claims being released
     * @param tokensReleased The total amount of tokens being released
     */
    event StakeClaimsReleased(address indexed serviceProvider, uint256 claimsCount, uint256 tokensReleased);

    /**
     * @notice Thrown when attempting to get a stake claim that does not exist.
     * @param claimId The id of the stake claim
     */
    error StakeClaimsClaimNotFound(bytes32 claimId);

    /**
     * @notice Emitted when trying to lock zero tokens in a stake claim
     */
    error StakeClaimsZeroTokens();

    /**
     * @notice Locks stake for a service provider to back a payment.
     * Creates a stake claim, which is stored in a linked list by service provider.
     * @dev Requirements:
     * - The associated provision must have enough available tokens to lock the stake.
     *
     * Emits a {StakeClaimLocked} event.
     *
     * @param feesProvisionTracker The mapping that tracks the provision tokens for each service provider
     * @param claims The mapping that stores stake claims by their ID
     * @param claimsLists The mapping that stores linked lists of stake claims by service provider
     * @param graphStaking The Horizon staking contract used to lock the tokens
     * @param _dataService The address of the data service
     * @param _delegationRatio The delegation ratio to use for the stake claim
     * @param _serviceProvider The address of the service provider
     * @param _tokens The amount of tokens to lock in the claim
     * @param _unlockTimestamp The timestamp when the tokens can be released
     */
    function lockStake(
        mapping(address => uint256) storage feesProvisionTracker,
        mapping(bytes32 => StakeClaim) storage claims,
        mapping(address serviceProvider => LinkedList.List list) storage claimsLists,
        IHorizonStaking graphStaking,
        address _dataService,
        uint32 _delegationRatio,
        address _serviceProvider,
        uint256 _tokens,
        uint256 _unlockTimestamp
    ) external {
        require(_tokens != 0, StakeClaimsZeroTokens());
        feesProvisionTracker.lock(graphStaking, _serviceProvider, _tokens, _delegationRatio);

        LinkedList.List storage claimsList = claimsLists[_serviceProvider];

        // Save item and add to list
        bytes32 claimId = _buildStakeClaimId(_dataService, _serviceProvider, claimsList.nonce);
        claims[claimId] = StakeClaim({
            tokens: _tokens,
            createdAt: block.timestamp,
            releasableAt: _unlockTimestamp,
            nextClaim: bytes32(0)
        });
        if (claimsList.count != 0) claims[claimsList.tail].nextClaim = claimId;
        claimsList.addTail(claimId);

        emit StakeClaimLocked(_serviceProvider, claimId, _tokens, _unlockTimestamp);
    }

    /**
     * @notice Processes a stake claim, releasing the tokens if the claim has expired.
     * @dev This function is used as a callback in the stake claims linked list traversal.
     * @param feesProvisionTracker The mapping that tracks the provision tokens for each service provider.
     * @param claims The mapping that stores stake claims by their ID.
     * @param _claimId The ID of the stake claim to process.
     * @param _acc The accumulator data, which contains the total tokens claimed and the service provider address.
     * @return Whether the stake claim is still locked, indicating that the traversal should continue or stop.
     * @return The updated accumulator data
     */
    function processStakeClaim(
        mapping(address serviceProvider => uint256 tokens) storage feesProvisionTracker,
        mapping(bytes32 claimId => StakeClaim claim) storage claims,
        bytes32 _claimId,
        bytes memory _acc
    ) external returns (bool, bytes memory) {
        StakeClaim memory claim = claims[_claimId];
        require(claim.createdAt != 0, StakeClaimsClaimNotFound(_claimId));

        // early exit
        if (claim.releasableAt > block.timestamp) {
            return (true, LinkedList.NULL_BYTES);
        }

        // decode
        (uint256 tokensClaimed, address serviceProvider) = abi.decode(_acc, (uint256, address));

        // process
        feesProvisionTracker.release(serviceProvider, claim.tokens);
        emit StakeClaimReleased(serviceProvider, _claimId, claim.tokens, claim.releasableAt);

        // encode
        _acc = abi.encode(tokensClaimed + claim.tokens, serviceProvider);
        return (false, _acc);
    }

    /**
     * @notice Deletes a stake claim.
     * @dev This function is used as a callback in the stake claims linked list traversal.
     * @param claims The mapping that stores stake claims by their ID
     * @param claimId The ID of the stake claim to delete
     */
    function deleteStakeClaim(mapping(bytes32 claimId => StakeClaim claim) storage claims, bytes32 claimId) external {
        delete claims[claimId];
    }

    /**
     * @notice Gets the next stake claim in the linked list
     * @dev This function is used as a callback in the stake claims linked list traversal.
     * @param claims The mapping that stores stake claims by their ID
     * @param claimId The ID of the stake claim
     * @return The next stake claim ID
     */
    function getNextStakeClaim(
        mapping(bytes32 claimId => StakeClaim claim) storage claims,
        bytes32 claimId
    ) external view returns (bytes32) {
        return claims[claimId].nextClaim;
    }

    /**
     * @notice Builds a stake claim ID
     * @param dataService The address of the data service
     * @param serviceProvider The address of the service provider
     * @param nonce A nonce of the stake claim
     * @return The stake claim ID
     */
    function buildStakeClaimId(
        address dataService,
        address serviceProvider,
        uint256 nonce
    ) public pure returns (bytes32) {
        return _buildStakeClaimId(dataService, serviceProvider, nonce);
    }

    /**
     * @notice Builds a stake claim ID
     * @param _dataService The address of the data service
     * @param _serviceProvider The address of the service provider
     * @param _nonce A nonce of the stake claim
     * @return The stake claim ID
     */
    function _buildStakeClaimId(
        address _dataService,
        address _serviceProvider,
        uint256 _nonce
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_dataService, _serviceProvider, _nonce));
    }
}
