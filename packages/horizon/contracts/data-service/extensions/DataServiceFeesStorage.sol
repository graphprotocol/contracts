// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { IDataServiceFees } from "../interfaces/IDataServiceFees.sol";
import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";

import { LinkedList } from "../../libraries/LinkedList.sol";

abstract contract DataServiceFeesV1Storage {
    mapping(IGraphPayments.PaymentTypes feeType => mapping(address serviceProvider => uint256 tokens))
        public feesProvisionTracker;

    /// @notice List of all locked stake claims to be released to service providers
    mapping(bytes32 claimId => IDataServiceFees.StakeClaim claim) public claims;

    /// @notice Service providers registered in the data service
    mapping(IGraphPayments.PaymentTypes feeType => mapping(address serviceProvider => LinkedList.List list))
        public claimsLists;

    /// @dev Gap to allow adding variables in future upgrades
    uint256[50] private __gap;
}
