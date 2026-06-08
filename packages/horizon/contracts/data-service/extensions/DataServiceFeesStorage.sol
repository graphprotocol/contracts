// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { StakeClaims } from "../libraries/StakeClaims.sol";

import { ILinkedList } from "@graphprotocol/interfaces/contracts/horizon/internal/ILinkedList.sol";

/**
 * @title Storage layout for the {DataServiceFees} extension contract.
 * @author Edge & Node
 * @notice Storage layout for the DataServiceFees extension contract
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
abstract contract DataServiceFeesV1Storage {
    /// @notice The amount of tokens locked in stake claims for each service provider
    mapping(address serviceProvider => uint256 tokens) public feesProvisionTracker;

    /// @notice List of all locked stake claims to be released to service providers
    mapping(bytes32 claimId => StakeClaims.StakeClaim claim) public claims;

    /// @notice Service providers registered in the data service
    mapping(address serviceProvider => ILinkedList.List list) public claimsLists;

    // forge-lint: disable-next-item(mixed-case-variable)
    /// @dev Gap to allow adding variables in future upgrades
    /// Note that this contract is not upgradeable but might be inherited by an upgradeable contract
    uint256[50] private __gap;
}
