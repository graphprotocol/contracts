// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import { ProvisionTracker } from "../../../contracts/data-service/libraries/ProvisionTracker.sol";

contract ProvisionTrackerImplementation {
    mapping(address => uint256) public provisionTracker;
}
