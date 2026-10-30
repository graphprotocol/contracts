// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

import { ICuration } from "./ICuration.sol";
import { IGraphCurationToken } from "./IGraphCurationToken.sol";
import { Managed } from "../governance/Managed.sol";

/**
 * @title Curation Storage version 1
 * @dev This contract holds the first version of the storage variables
 * for the Curation and L2Curation contracts.
 * When adding new variables, create a new version that inherits this and update
 * the contracts to use the new version instead.
 */
abstract contract CurationV1Storage is Managed, ICuration {
    // -- Pool --

    /**
     * @dev CurationPool structure that holds the pool's state
     * for a particular subgraph deployment.
     */
    struct CurationPool {
        uint256 tokens; // GRT Tokens stored as reserves for the subgraph deployment
        uint32 reserveRatio; // Ratio for the bonding curve, unused and deprecated in L2 where it will always be 100% but appear as 0
        IGraphCurationToken gcs; // Curation token contract for this curation pool
    }

    // -- State --

    /// Tax charged when curators deposit funds.
    /// Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public override curationTaxPercentage;

    /// Default reserve ratio to configure curator shares bonding curve
    /// Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%).
    /// Unused in L2.
    uint32 public defaultReserveRatio;

    /// Master copy address that holds implementation of curation token.
    /// @dev This is used as the target for GraphCurationToken clones.
    address public curationTokenMaster;

    /// Minimum amount allowed to be deposited by curators to initialize a pool
    /// @dev This is the `startPoolBalance` for the bonding curve
    uint256 public minimumCurationDeposit;

    /// Bonding curve library
    /// Unused in L2.
    address public bondingCurve;

    /// @dev Mapping of subgraphDeploymentID => CurationPool
    /// There is only one CurationPool per SubgraphDeploymentID
    mapping(bytes32 => CurationPool) public pools;
}

/**
 * @title Curation Storage version 2
 * @dev This contract holds the second version of the storage variables
 * for the Curation and L2Curation contracts.
 * It doesn't add new variables at this contract's level, but adds the Initializable
 * contract to the inheritance chain, which includes storage variables.
 * When adding new variables, create a new version that inherits this and update
 * the contracts to use the new version instead.
 */
abstract contract CurationV2Storage is CurationV1Storage, Initializable {
    // Nothing here, just adding Initializable
}
