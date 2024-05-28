// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { IDataService } from "./IDataService.sol";

interface IDataServiceFees is IDataService {
    /// A locked stake claim to be released to a service provider
    struct StakeClaim {
        address serviceProvider;
        // tokens to be released with this claim
        uint256 tokens;
        uint256 createdAt;
        // timestamp when the claim can be released
        uint256 releaseAt;
        // next claim in the linked list
        bytes32 nextClaim;
    }

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
    event StakeClaimsReleased(address indexed serviceProvider, uint256 claimsCount, uint256 tokensReleased);

    error DataServiceFeesClaimNotFound(bytes32 claimId);

    function releaseStake(uint256 n) external;
}
