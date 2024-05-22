// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IDataServiceFees } from "./IDataServiceFees.sol";
import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";

import { ProvisionTracker } from "../libraries/ProvisionTracker.sol";

import { DataService } from "../DataService.sol";
import { DataServiceFeesV1Storage } from "./DataServiceFeesStorage.sol";

abstract contract DataServiceFees is DataService, DataServiceFeesV1Storage, IDataServiceFees {
    using ProvisionTracker for mapping(address => uint256);

    event StakeClaimLocked(
        address indexed serviceProvider,
        bytes32 indexed claimId,
        uint256 tokens,
        uint256 unlockTimestamp
    );
    event StakeClaimReleased(
        address indexed serviceProvider,
        bytes32 indexed claimId,
        uint256 tokens,
        uint256 releaseAt
    );

    error DataServiceFeesClaimNotFound(bytes32 claimId);

    function releaseStake(IGraphPayments.PaymentTypes feeType, uint256 n) external virtual {
        _releaseStake(feeType, msg.sender, n);
    }

    /// @notice Release expired stake claims for a service provider
    /// @param _n The number of stake claims to release, or 0 to release all
    function _releaseStake(IGraphPayments.PaymentTypes _feeType, address _serviceProvider, uint256 _n) internal {
        bool releaseAll = _n == 0;

        // check the stake claims list
        // TODO: evaluate replacing with OZ DoubleEndedQueue
        bytes32 head = claimsLists[_feeType][_serviceProvider].head;
        while (head != bytes32(0) && (releaseAll || _n > 0)) {
            StakeClaim memory claim = _getStakeClaim(head);

            if (block.timestamp >= claim.releaseAt) {
                // Release stake
                feesProvisionTracker[_feeType].release(_serviceProvider, claim.tokens);

                // Update list and refresh pointer
                StakeClaimsList storage claimsList = claimsLists[_feeType][_serviceProvider];
                claimsList.head = claim.nextClaim;
                delete claims[head];
                head = claimsList.head;
                if (!releaseAll) _n--;

                emit StakeClaimReleased(_serviceProvider, claimsList.head, claim.tokens, claim.releaseAt);
            } else {
                break;
            }
        }
    }

    function _lockStake(
        IGraphPayments.PaymentTypes _feeType,
        address _serviceProvider,
        uint256 _tokens,
        uint256 _unlockTimestamp
    ) internal {
        feesProvisionTracker[_feeType].lock(_graphStaking(), _serviceProvider, _tokens, maximumDelegationRatio);

        StakeClaimsList storage claimsList = claimsLists[_feeType][_serviceProvider];
        bytes32 claimId = _buildStakeClaimId(_serviceProvider, claimsList.nonce);
        claims[claimId] = StakeClaim({
            serviceProvider: _serviceProvider,
            tokens: _tokens,
            createdAt: block.timestamp,
            releaseAt: _unlockTimestamp,
            nextClaim: bytes32(0)
        });

        claims[claimsList.tail].nextClaim = claimId;
        claimsList.tail = claimId;
        claimsList.nonce += 1;

        emit StakeClaimLocked(_serviceProvider, claimId, _tokens, _unlockTimestamp);
    }

    function _getStakeClaim(bytes32 _claimId) private view returns (StakeClaim memory) {
        StakeClaim memory claim = claims[_claimId];
        if (claim.createdAt == 0) {
            revert DataServiceFeesClaimNotFound(_claimId);
        }
        return claim;
    }

    function _buildStakeClaimId(address _serviceProvider, uint256 _nonce) private view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), _serviceProvider, _nonce));
    }
}
