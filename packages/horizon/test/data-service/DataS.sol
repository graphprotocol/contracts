// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import { IGraphPayments } from "../../contracts/interfaces/IGraphPayments.sol";
import { IDataServiceFees } from "../../contracts/data-service/interfaces/IDataServiceFees.sol";

import { LinkedList } from "../../contracts/libraries/LinkedList.sol";
import "forge-std/console.sol";

contract DataS {
    using LinkedList for LinkedList.List;
    struct StakeClaim {
        uint256 tokens;
        uint256 releaseAt;
        bytes32 nextClaim;
    }

    mapping(bytes32 claimId => StakeClaim tokens) public claims;
    /// @notice Service providers registered in the data service
    mapping(address serviceProvider => LinkedList.List list) public claimsLists2;

    constructor() {}

    function lockStake(address sp, uint256 tokens, uint256 unlock) external {
        _lockStake(sp, tokens, unlock);
    }

    function releaseStake2(address _serviceProvider, uint256 _n) external {
        LinkedList.List storage claimsList2 = claimsLists2[_serviceProvider];
        (uint256 count, bytes memory acc) = claimsList2.traverse(
            _getNextStakeClaim,
            _processStakeClaim,
            _deleteStakeClaim,
            abi.encode(0),
            _n
        );

        uint256 tokens = abi.decode(acc, (uint256));

        console.log("count: %s", count);
        console.log("tokens accumualted: %s", tokens);
    }

    function _lockStake(address _serviceProvider, uint256 _tokens, uint256 _unlockTimestamp) internal {
        LinkedList.List storage claimsList = claimsLists2[_serviceProvider];
        bytes32 claimId = _buildStakeClaimId(_serviceProvider, claimsList.nonce);
        claims[claimId] = StakeClaim({ tokens: _tokens, releaseAt: _unlockTimestamp, nextClaim: bytes32(0) });
        console.logBytes32(claimId);
        claims[claimsList.tail].nextClaim = claimId;

        claimsList.tail = claimId;
        claimsList.nonce += 1;
        if (claimsList.head == bytes32(0)) claimsList.head = claimId;
    }

    function _buildStakeClaimId(address _serviceProvider, uint256 _nonce) private view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), _serviceProvider, _nonce));
    }

    function _getStakeClaim(bytes32 _claimId) private view returns (StakeClaim memory) {
        StakeClaim memory claim = claims[_claimId];
        return claim;
    }

    function _getNextStakeClaim(bytes32 _claimId) private view returns (bytes32) {
        StakeClaim memory claim = claims[_claimId];
        return claim.nextClaim;
    }

    function _deleteStakeClaim(bytes32 _claimId) private {
        delete claims[_claimId];
    }

    function _processStakeClaim(
        bytes32 _claimId,
        bytes memory acc_
    ) private returns (bool, bool, bytes memory) {
        StakeClaim memory claim = _getStakeClaim(_claimId);
        if (block.timestamp < claim.releaseAt) return (true, false, LinkedList.NULL_BYTES);

        uint256 tokensAcc = abi.decode(acc_, (uint256));
        return (block.timestamp < claim.releaseAt, true, abi.encode(tokensAcc + claim.tokens));
    }
}
