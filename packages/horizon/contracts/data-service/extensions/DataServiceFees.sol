// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { IDataServiceFees } from "../interfaces/IDataServiceFees.sol";

import { ProvisionTracker } from "../libraries/ProvisionTracker.sol";
import { LinkedList } from "../../libraries/LinkedList.sol";

import { DataService } from "../DataService.sol";
import { DataServiceFeesV1Storage } from "./DataServiceFeesStorage.sol";

/**
 * @title DataServiceFees contract
 * @dev Implementation of the {IDataServiceFees} interface.
 * @notice Extension for the {IDataService} contract to handle payment collateralization
 * using a Horizon provision. See {IDataServiceFees} for more details.
 */
abstract contract DataServiceFees is DataService, DataServiceFeesV1Storage, IDataServiceFees {
    using ProvisionTracker for mapping(address => uint256);
    using LinkedList for LinkedList.List;

    /**
     * @notice See {IDataServiceFees-releaseStake}
     */
    function releaseStake(uint256 n) external virtual {
        _releaseStake(msg.sender, n);
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
        feesProvisionTracker.lock(_graphStaking(), _serviceProvider, _tokens, maximumDelegationRatio);

        LinkedList.List storage claimsList = claimsLists[_serviceProvider];

        // Save item and add to list
        bytes32 claimId = _buildStakeClaimId(_serviceProvider, claimsList.nonce);
        claims[claimId] = StakeClaim({
            tokens: _tokens,
            createdAt: block.timestamp,
            releaseAt: _unlockTimestamp,
            nextClaim: bytes32(0)
        });
        if (claimsList.count != 0) claims[claimsList.tail].nextClaim = claimId;
        claimsList.add(claimId);

        emit StakeClaimLocked(_serviceProvider, claimId, _tokens, _unlockTimestamp);
    }

    /**
     * @notice See {IDataServiceFees-releaseStake}
     */
    function _releaseStake(address _serviceProvider, uint256 _n) internal {
        LinkedList.List storage claimsList = claimsLists[_serviceProvider];
        (uint256 claimsReleased, bytes memory data) = claimsList.traverse(
            _getNextStakeClaim,
            _processStakeClaim,
            _deleteStakeClaim,
            abi.encode(0, _serviceProvider),
            _n
        );

        emit StakeClaimsReleased(_serviceProvider, claimsReleased, abi.decode(data, (uint256)));
    }

    /**
     * @notice Processes a stake claim, releasing the tokens if the claim has expired.
     * @dev This function is used as a callback in the stake claims linked list traversal.
     * @param _claimId The id of the stake claim
     * @param _acc The accumulator for the stake claims being processed
     * @return Wether the stake claim is still locked, indicating that the traversal should continue or stop.
     * @return Wether the stake claim should be deleted
     * @return The updated accumulator data
     */
    function _processStakeClaim(bytes32 _claimId, bytes memory _acc) private returns (bool, bool, bytes memory) {
        StakeClaim memory claim = _getStakeClaim(_claimId);

        // early exit
        if (claim.releaseAt > block.timestamp) {
            return (true, false, LinkedList.NULL_BYTES);
        }

        // decode
        (uint256 tokensClaimed, address serviceProvider) = abi.decode(_acc, (uint256, address));

        // process
        feesProvisionTracker.release(serviceProvider, claim.tokens);
        emit StakeClaimReleased(serviceProvider, _claimId, claim.tokens, claim.releaseAt);

        // encode
        _acc = abi.encode(tokensClaimed + claim.tokens, serviceProvider);
        return (false, true, _acc);
    }

    /**
     * @notice Deletes a stake claim.
     * @dev This function is used as a callback in the stake claims linked list traversal.
     * @param _claimId The ID of the stake claim to delete
     */
    function _deleteStakeClaim(bytes32 _claimId) private {
        delete claims[_claimId];
    }

    /**
     * @notice Gets the details of a stake claim
     * @param _claimId The ID of the stake claim
     */
    function _getStakeClaim(bytes32 _claimId) private view returns (StakeClaim memory) {
        StakeClaim memory claim = claims[_claimId];
        require(claim.createdAt != 0, DataServiceFeesClaimNotFound(_claimId));
        return claim;
    }

    /**
     * @notice Gets the next stake claim in the linked list
     * @dev This function is used as a callback in the stake claims linked list traversal.
     * @param _claimId The ID of the stake claim
     */
    function _getNextStakeClaim(bytes32 _claimId) private view returns (bytes32) {
        StakeClaim memory claim = claims[_claimId];
        require(claim.createdAt != 0, DataServiceFeesClaimNotFound(_claimId));
        return claim.nextClaim;
    }

    /**
     * @notice Builds a stake claim ID
     * @param _serviceProvider The address of the service provider
     * @param _nonce A nonce of the stake claim
     */
    function _buildStakeClaimId(address _serviceProvider, uint256 _nonce) private view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), _serviceProvider, _nonce));
    }
}
