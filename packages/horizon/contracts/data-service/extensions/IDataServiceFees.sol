// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IDataService } from "../../interfaces/IDataService.sol";
import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";

interface IDataServiceFees is IDataService {
    struct StakeClaimsList {
        bytes32 head;
        bytes32 tail;
        uint256 nonce;
    }

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

    function releaseStake(IGraphPayments.PaymentTypes feeType, uint256 n) external;
}
