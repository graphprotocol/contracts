// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IDataServiceFees } from "../interfaces/IDataServiceFees.sol";

import { ProvisionTracker } from "../libraries/ProvisionTracker.sol";
import { LinkedList } from "../../libraries/LinkedList.sol";
import { StakeClaims } from "../libraries/StakeClaims.sol";

import { DataService } from "../DataService.sol";
import { DataServiceFeesV1Storage } from "./DataServiceFeesStorage.sol";

/**
 * @title DataServiceFees contract
 * @dev Implementation of the {IDataServiceFees} interface.
 * @notice Extension for the {IDataService} contract to handle payment collateralization
 * using a Horizon provision. See {IDataServiceFees} for more details.
 * @dev This contract inherits from {DataService} which needs to be initialized, please see
 * {DataService} for detailed instructions.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
abstract contract DataServiceFees is DataService, DataServiceFeesV1Storage, IDataServiceFees {
    using ProvisionTracker for mapping(address => uint256);
    using LinkedList for LinkedList.List;

    /// @inheritdoc IDataServiceFees
    function releaseStake(uint256 numClaimsToRelease) external virtual override {
        _releaseStake(msg.sender, numClaimsToRelease);
    }

    /**
     * @notice Locks stake for a service provider to back a payment.
     * Creates a stake claim, which is stored in a linked list by service provider.
     * @dev Requirements:
     * - The associated provision must have enough available tokens to lock the stake.
     *
     * Emits a {StakeClaimLocked} event.
     *
     * @param _serviceProvider The address of the service provider
     * @param _tokens The amount of tokens to lock in the claim
     * @param _unlockTimestamp The timestamp when the tokens can be released
     */
    function _lockStake(address _serviceProvider, uint256 _tokens, uint256 _unlockTimestamp) internal {
        StakeClaims.lockStake(
            feesProvisionTracker,
            claims,
            claimsLists,
            _graphStaking(),
            address(this),
            _delegationRatio,
            _serviceProvider,
            _tokens,
            _unlockTimestamp
        );
    }

    /**
     * @notice Releases expired stake claims for a service provider.
     * @dev This function can be overriden and/or disabled.
     * @dev Note that the list is traversed by creation date not by releasableAt date. Traversing will stop
     * when the first stake claim that is not yet expired is found even if later stake claims have expired. This
     * could happen if stake claims are genereted with different unlock periods.
     * @dev Emits a {StakeClaimsReleased} event, and a {StakeClaimReleased} event for each claim released.
     * @param _serviceProvider The address of the service provider
     * @param _numClaimsToRelease Amount of stake claims to process. If 0, all stake claims are processed.
     */
    function _releaseStake(address _serviceProvider, uint256 _numClaimsToRelease) internal {
        LinkedList.List storage claimsList = claimsLists[_serviceProvider];
        (uint256 claimsReleased, bytes memory data) = claimsList.traverse(
            _getNextStakeClaim,
            _processStakeClaim,
            _deleteStakeClaim,
            abi.encode(0, _serviceProvider),
            _numClaimsToRelease
        );

        emit StakeClaims.StakeClaimsReleased(_serviceProvider, claimsReleased, abi.decode(data, (uint256)));
    }

    /**
     * @notice Processes a stake claim, releasing the tokens if the claim has expired.
     * @dev This function is used as a callback in the stake claims linked list traversal.
     * @param _claimId The id of the stake claim
     * @param _acc The accumulator for the stake claims being processed
     * @return Whether the stake claim is still locked, indicating that the traversal should continue or stop.
     * @return The updated accumulator data
     */
    function _processStakeClaim(bytes32 _claimId, bytes memory _acc) private returns (bool, bytes memory) {
        return StakeClaims.processStakeClaim(feesProvisionTracker, claims, _claimId, _acc);
    }

    /**
     * @notice Deletes a stake claim.
     * @dev This function is used as a callback in the stake claims linked list traversal.
     * @param _claimId The ID of the stake claim to delete
     */
    function _deleteStakeClaim(bytes32 _claimId) private {
        StakeClaims.deleteStakeClaim(claims, _claimId);
    }

    /**
     * @notice Gets the next stake claim in the linked list
     * @dev This function is used as a callback in the stake claims linked list traversal.
     * @param _claimId The ID of the stake claim
     * @return The next stake claim ID
     */
    function _getNextStakeClaim(bytes32 _claimId) private view returns (bytes32) {
        return StakeClaims.getNextStakeClaim(claims, _claimId);
    }
}
