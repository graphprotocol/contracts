// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { IDataServiceFees } from "../interfaces/IDataServiceFees.sol";

import { ProvisionTracker } from "../libraries/ProvisionTracker.sol";
import { LinkedList } from "../../libraries/LinkedList.sol";

import { DataService } from "../DataService.sol";
import { DataServiceFeesV1Storage } from "./DataServiceFeesStorage.sol";

abstract contract DataServiceFees is DataService, DataServiceFeesV1Storage, IDataServiceFees {
    using ProvisionTracker for mapping(address => uint256);
    using LinkedList for LinkedList.List;

    function releaseStake(uint256 n) external virtual {
        _releaseStake(msg.sender, n);
    }

    function _lockStake(address _serviceProvider, uint256 _tokens, uint256 _unlockTimestamp) internal {
        feesProvisionTracker.lock(_graphStaking(), _serviceProvider, _tokens, maximumDelegationRatio);

        LinkedList.List storage claimsList = claimsLists[_serviceProvider];

        // Save item and add to list
        bytes32 claimId = _buildStakeClaimId(_serviceProvider, claimsList.nonce);
        claims[claimId] = StakeClaim({
            serviceProvider: _serviceProvider,
            tokens: _tokens,
            createdAt: block.timestamp,
            releaseAt: _unlockTimestamp,
            nextClaim: bytes32(0)
        });
        if (claimsList.count != 0) claims[claimsList.tail].nextClaim = claimId;
        claimsList.add(claimId);

        emit StakeClaimLocked(_serviceProvider, claimId, _tokens, _unlockTimestamp);
    }

    /// @notice Release expired stake claims for a service provider
    /// @param _n The number of stake claims to release, or 0 to release all
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

    function _deleteStakeClaim(bytes32 _claimId) private {
        delete claims[_claimId];
    }

    function _getStakeClaim(bytes32 _claimId) private view returns (StakeClaim memory) {
        StakeClaim memory claim = claims[_claimId];
        require(claim.createdAt != 0, DataServiceFeesClaimNotFound(_claimId));
        return claim;
    }

    function _getNextStakeClaim(bytes32 _claimId) private view returns (bytes32) {
        StakeClaim memory claim = claims[_claimId];
        require(claim.createdAt != 0, DataServiceFeesClaimNotFound(_claimId));
        return claim.nextClaim;
    }

    function _buildStakeClaimId(address _serviceProvider, uint256 _nonce) private view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), _serviceProvider, _nonce));
    }
}
