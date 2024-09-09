// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IDataService } from "./IDataService.sol";

/**
 * @title Interface for the {DataServiceFees} contract.
 * @notice Extension for the {IDataService} contract to handle payment collateralization
 * using a Horizon provision.
 *
 * It's designed to be used with the Data Service framework:
 * - When a service provider collects payment with {IDataService.collect} the data service should lock
 *   stake to back the payment using {_lockStake}.
 * - Every time there is a payment collection with {IDataService.collect}, the data service should
 *   attempt to release any expired stake claims by calling {_releaseStake}.
 * - Stake claims can also be manually released by calling {releaseStake} directly.
 *
 * @dev Note that this implementation uses the entire provisioned stake as collateral for the payment.
 * It can be used to provide economic security for the payments collected as long as the provisioned
 * stake is not being used for other purposes.
 */
interface IDataServiceFees is IDataService {
    /**
     * @notice A stake claim, representing provisioned stake that gets locked
     * to be released to a service provider.
     * @dev StakeClaims are stored in linked lists by service provider, ordered by
     * creation timestamp.
     */
    struct StakeClaim {
        // The amount of tokens to be locked in the claim
        uint256 tokens;
        // Timestamp when the claim was created
        uint256 createdAt;
        // Timestamp when the claim will expire and tokens can be released
        uint256 releaseAt;
        // Next claim in the linked list
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
     * @param releaseAt The timestamp when the tokens were released
     */
    event StakeClaimReleased(
        address indexed serviceProvider,
        bytes32 indexed claimId,
        uint256 tokens,
        uint256 releaseAt
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
     */
    error DataServiceFeesClaimNotFound(bytes32 claimId);

    /**
     * @notice Emitted when trying to lock zero tokens in a stake claim
     */
    error DataServiceFeesZeroTokens();

    /**
     * @notice Releases expired stake claims for the caller.
     * @dev This function is only meant to be called if the service provider has enough
     * stake claims that releasing them all at once would exceed the block gas limit.
     * @dev This function can be overriden and/or disabled.
     * @dev Emits a {StakeClaimsReleased} event, and a {StakeClaimReleased} event for each claim released.
     * @param n Amount of stake claims to process. If 0, all stake claims are processed.
     */
    function releaseStake(uint256 n) external;
}
