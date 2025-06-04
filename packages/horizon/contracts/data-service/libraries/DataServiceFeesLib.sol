// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { ProvisionTracker } from "./ProvisionTracker.sol";
import { IDataServiceFees } from "../interfaces/IDataServiceFees.sol";
import { IHorizonStaking } from "../../interfaces/IHorizonStaking.sol";
import { LinkedList } from "../../libraries/LinkedList.sol";

library DataServiceFeesLib {
    using ProvisionTracker for mapping(address => uint256);
    using LinkedList for LinkedList.List;

    // @notice Storage structure for the provision manager
    struct ProvisionManagerStorage {
        uint256 _minimumProvisionTokens;
        uint256 _maximumProvisionTokens;
        uint64 _minimumThawingPeriod;
        uint64 _maximumThawingPeriod;
        uint32 _minimumVerifierCut;
        uint32 _maximumVerifierCut;
        uint32 _delegationRatio;
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
    function lockStake(
        mapping(address => uint256) storage feesProvisionTracker,
        mapping(bytes32 => IDataServiceFees.StakeClaim) storage claims,
        mapping(address serviceProvider => LinkedList.List list) storage claimsLists,
        IHorizonStaking graphStaking,
        uint32 _delegationRatio,
        address _serviceProvider,
        uint256 _tokens,
        uint256 _unlockTimestamp
    ) external {
        require(_tokens != 0, IDataServiceFees.DataServiceFeesZeroTokens());
        feesProvisionTracker.lock(graphStaking, _serviceProvider, _tokens, _delegationRatio);

        LinkedList.List storage claimsList = claimsLists[_serviceProvider];

        // Save item and add to list
        bytes32 claimId = _buildStakeClaimId(_serviceProvider, claimsList.nonce);
        claims[claimId] = IDataServiceFees.StakeClaim({
            tokens: _tokens,
            createdAt: block.timestamp,
            releasableAt: _unlockTimestamp,
            nextClaim: bytes32(0)
        });
        if (claimsList.count != 0) claims[claimsList.tail].nextClaim = claimId;
        claimsList.addTail(claimId);

        emit IDataServiceFees.StakeClaimLocked(_serviceProvider, claimId, _tokens, _unlockTimestamp);
    }

    /**
     * @notice Processes a stake claim, releasing the tokens if the claim has expired.
     * @dev This function is used as a callback in the stake claims linked list traversal.
     * @return Whether the stake claim is still locked, indicating that the traversal should continue or stop.
     * @return The updated accumulator data
     */
    function processStakeClaim(
        mapping(address serviceProvider => uint256 tokens) storage feesProvisionTracker,
        mapping(bytes32 claimId => IDataServiceFees.StakeClaim claim) storage claims,
        bytes32 _claimId,
        bytes memory _acc
    ) external returns (bool, bytes memory) {
        IDataServiceFees.StakeClaim memory claim = claims[_claimId];
        require(claim.createdAt != 0, IDataServiceFees.DataServiceFeesClaimNotFound(_claimId));

        // early exit
        if (claim.releasableAt > block.timestamp) {
            return (true, LinkedList.NULL_BYTES);
        }

        // decode
        (uint256 tokensClaimed, address serviceProvider) = abi.decode(_acc, (uint256, address));

        // process
        feesProvisionTracker.release(serviceProvider, claim.tokens);
        emit IDataServiceFees.StakeClaimReleased(serviceProvider, _claimId, claim.tokens, claim.releasableAt);

        // encode
        _acc = abi.encode(tokensClaimed + claim.tokens, serviceProvider);
        return (false, _acc);
    }

    /**
     * @notice Builds a stake claim ID
     * @param serviceProvider The address of the service provider
     * @param nonce A nonce of the stake claim
     * @return The stake claim ID
     */
    function _buildStakeClaimId(address serviceProvider, uint256 nonce) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), serviceProvider, nonce));
    }
}
