// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { ICuration } from "./ICuration.sol";
import { IGraphCurationToken } from "./IGraphCurationToken.sol";
import { Managed } from "../governance/Managed.sol";

abstract contract CurationV1Storage is Managed, ICuration {
    // -- Pool --

    struct CurationPool {
        uint256 tokens; // GRT Tokens stored as reserves for the subgraph deployment
        uint32 reserveRatio; // Ratio for the bonding curve
        IGraphCurationToken gcs; // Curation token contract for this curation pool
    }

    // -- State --

    // Tax charged when curator deposit funds
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public override curationTaxPercentage;

    // Default reserve ratio to configure curator shares bonding curve
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public defaultReserveRatio;

    // Master copy address that holds implementation of curation token
    // This is used as the target for GraphCurationToken clones
    address public curationTokenMaster;

    // Minimum amount allowed to be deposited by curators to initialize a pool
    // This is the `startPoolBalance` for the bonding curve
    uint256 public minimumCurationDeposit;

    // Bonding curve library
    address public bondingCurve;

    // Mapping of subgraphDeploymentID => CurationPool
    // There is only one CurationPool per SubgraphDeploymentID
    mapping(bytes32 => CurationPool) public pools;
}
