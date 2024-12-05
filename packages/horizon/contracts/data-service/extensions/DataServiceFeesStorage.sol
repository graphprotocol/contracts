// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IDataServiceFees } from "../interfaces/IDataServiceFees.sol";

import { LinkedList } from "../../libraries/LinkedList.sol";

/**
 * @title Storage layout for the {DataServiceFees} extension contract.
 */
abstract contract DataServiceFeesV1Storage {
    mapping(address serviceProvider => uint256 tokens) public feesProvisionTracker;

    /// @notice List of all locked stake claims to be released to service providers
    mapping(bytes32 claimId => IDataServiceFees.StakeClaim claim) public claims;

    /// @notice Service providers registered in the data service
    mapping(address serviceProvider => LinkedList.List list) public claimsLists;

    /// @dev Gap to allow adding variables in future upgrades
    /// Note that this contract is not upgradeable but might be inherited by an upgradeable contract
    uint256[50] private __gap;
}
