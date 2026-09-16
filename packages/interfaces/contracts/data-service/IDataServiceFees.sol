// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events

import { IDataService } from "./IDataService.sol";

/**
 * @title Interface for the {DataServiceFees} contract.
 * @author Edge & Node
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
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IDataServiceFees is IDataService {
    /**
     * @notice Releases expired stake claims for the caller.
     * @dev This function is only meant to be called if the service provider has enough
     * stake claims that releasing them all at once would exceed the block gas limit.
     * @dev This function can be overriden and/or disabled.
     * @dev Emits a {StakeClaimsReleased} event, and a {StakeClaimReleased} event for each claim released.
     * @param numClaimsToRelease Amount of stake claims to process. If 0, all stake claims are processed.
     */
    function releaseStake(uint256 numClaimsToRelease) external;
}
