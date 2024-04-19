// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { DataService } from "../DataService.sol";
import { DataServiceFeesV1Storage } from "./DataServiceFeesStorage.sol";
import { IDataServiceFees } from "./IDataServiceFees.sol";
import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";

import { ProvisionTracker } from "../libraries/ProvisionTracker.sol";

abstract contract DataServiceFees is DataService, DataServiceFeesV1Storage, IDataServiceFees {
    using ProvisionTracker for mapping(address => uint256);

    error DataServiceFeesClaimNotFound(bytes32 claimId);

    event StakeClaimLocked(address serviceProvider, bytes32 claimId, uint256 tokens, uint256 unlockTimestamp);
    event StakeClaimReleased(address serviceProvider, bytes32 claimId, uint256 tokens, uint256 releaseAt);

    function lockStake(
        IGraphPayments.PaymentTypes feeType,
        address serviceProvider,
        uint256 tokens,
        uint256 unlockTimestamp
    ) internal {
        feesProvisionTracker[feeType].lock(graphStaking, serviceProvider, tokens);

        StakeClaimsList storage claimsList = claimsLists[feeType][serviceProvider];
        bytes32 claimId = _buildStakeClaimId(serviceProvider, claimsList.nonce);
        claims[claimId] = StakeClaim({
            serviceProvider: serviceProvider,
            tokens: tokens,
            createdAt: block.timestamp,
            releaseAt: unlockTimestamp,
            nextClaim: bytes32(0)
        });

        claims[claimsList.tail].nextClaim = claimId;
        claimsList.tail = claimId;
        claimsList.nonce += 1;

        emit StakeClaimLocked(serviceProvider, claimId, tokens, unlockTimestamp);
    }

    /// @notice Release expired stake claims for a service provider
    /// @param n The number of stake claims to release, or 0 to release all
    function releaseStake(IGraphPayments.PaymentTypes feeType, address serviceProvider, uint256 n) public {
        bool releaseAll = n == 0;

        // check the stake claims list
        // TODO: evaluate replacing with OZ DoubleEndedQueue
        bytes32 head = claimsLists[feeType][serviceProvider].head;
        while (head != bytes32(0) && (releaseAll || n > 0)) {
            StakeClaim memory claim = _getStakeClaim(head);

            if (block.timestamp >= claim.releaseAt) {
                // Release stake
                feesProvisionTracker[feeType].release(serviceProvider, claim.tokens);

                // Update list and refresh pointer
                StakeClaimsList storage claimsList = claimsLists[feeType][serviceProvider];
                claimsList.head = claim.nextClaim;
                delete claims[head];
                head = claimsList.head;
                if (!releaseAll) n--;

                emit StakeClaimReleased(serviceProvider, claimsList.head, claim.tokens, claim.releaseAt);
            } else {
                break;
            }
        }
    }

    function _getStakeClaim(bytes32 claimId) private view returns (StakeClaim memory) {
        StakeClaim memory claim = claims[claimId];
        if (claim.createdAt == 0) {
            revert DataServiceFeesClaimNotFound(claimId);
        }
        return claim;
    }

    function _buildStakeClaimId(address serviceProvider, uint256 nonce) private view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), serviceProvider, nonce));
    }
}
