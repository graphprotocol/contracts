// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IDataServiceFees } from "./IDataServiceFees.sol";

contract DataServiceFeesV1Storage {
    /// @notice List of locked stake claims to be released to service providers
    mapping(bytes32 claimId => IDataServiceFees.StakeClaim claim) public claims;

    /// @notice Service providers registered in the data service
    mapping(address serviceProvider => IDataServiceFees.FeesServiceProvider details) public feesServiceProviders;
}
