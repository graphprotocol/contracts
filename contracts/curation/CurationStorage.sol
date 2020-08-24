pragma solidity ^0.6.4;

import "../bancor/BancorFormula.sol";
import "./ICuration.sol";
import "../governance/Manager.sol";

contract CurationV1Storage is BancorFormula, Manager {
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

    // Total tokens in held as reserves received from curators deposits
    uint256 internal totalTokens;

    // Mapping of subgraphDeploymentID => CurationPool
    // There is only one CurationPool per SubgraphDeploymentID
    mapping(bytes32 => ICuration.CurationPool) public pools;
}
