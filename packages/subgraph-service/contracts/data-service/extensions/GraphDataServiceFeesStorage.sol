// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphDataServiceFees } from "./IGraphDataServiceFees.sol";

contract GraphDataServiceFeesV1Storage {
    /// @notice List of locked stake claims to be released to service providers
    mapping(bytes32 claimId => IGraphDataServiceFees.StakeClaim claim) public claims;

    /// @notice Service providers registered in the data service
    mapping(address serviceProvider => IGraphDataServiceFees.FeesServiceProvider details) public feesServiceProviders;
}
