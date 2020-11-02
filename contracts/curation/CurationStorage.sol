// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.3;

import "./ICuration.sol";
import "../governance/Managed.sol";

contract CurationV1Storage is Managed {
    // -- State --

    // Fee charged when curator withdraw a deposit
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public withdrawalFeePercentage;

    // Default reserve ratio to configure curator shares bonding curve
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public defaultReserveRatio;

    // Minimum amount allowed to be deposited by curators to initialize a pool
    // This is the `startPoolBalance` for the bonding curve
    uint256 public minimumCurationDeposit;

    // Bonding curve formula
    address public bondingCurve;

    // Mapping of subgraphDeploymentID => CurationPool
    // There is only one CurationPool per SubgraphDeploymentID
    mapping(bytes32 => ICuration.CurationPool) public pools;
}
