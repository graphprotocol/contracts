// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IDataServiceFees } from "./IDataServiceFees.sol";
import { ProvisionTracker } from "../libraries/ProvisionTracker.sol";
import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";

contract DataServiceFeesV1Storage {
    /// @notice List of all locked stake claims to be released to service providers
    mapping(bytes32 claimId => IDataServiceFees.StakeClaim claim) public claims;

    mapping(IGraphPayments.PaymentTypes feeType => mapping(address serviceProvider => uint256 tokens))
        public provisionTracker;

    /// @notice Service providers registered in the data service
    mapping(IGraphPayments.PaymentTypes feeType => mapping(address serviceProvider => IDataServiceFees.StakeClaimsList list))
        public claimsLists;
}
