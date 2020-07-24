pragma solidity ^0.6.4;

import "../bancor/BancorFormula.sol";
import "../staking/IStaking.sol";
import "../token/IGraphToken.sol";

import "./GraphSignalToken.sol";

contract CurationV1Storage is BancorFormula {
    // -- Pool --

    struct CurationPool {
        uint256 tokens; // GRT Tokens stored as reserves for the subgraph deployment
        uint32 reserveRatio; // Ratio for the bonding curve
        GraphSignalToken gst; // Signal token contract for this curation pool
    }

    // -- State --

    // Fee charged when curator withdraw stake
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public withdrawalFeePercentage;

    // Default reserve ratio to configure curator shares bonding curve
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public defaultReserveRatio;

    // Minimum amount allowed to be staked by curators
    // This is the `startPoolBalance` for the bonding curve
    uint256 public minimumCurationStake;

    // Mapping of subgraphDeploymentID => CurationPool
    // There is only one CurationPool per SubgraphDeploymentID
    mapping(bytes32 => CurationPool) public pools;

    // -- Related contracts --

    // Address of the staking contract that will distribute fees to reserves
    IStaking public staking;

    // Token used for staking
    IGraphToken public token;
}
