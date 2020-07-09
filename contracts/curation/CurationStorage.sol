pragma solidity ^0.6.4;

import "../IGraphToken.sol";
import "../Governed.sol";
import "../GraphProxyStorage.sol";
import "../bancor/BancorFormula.sol";

contract CurationV1Storage is GraphProxyStorage, BancorFormula {
    // -- Curation --

    struct CurationPool {
        uint256 tokens; // Tokens stored as reserves for the SubgraphDeployment
        uint256 shares; // Shares issued for the SubgraphDeployment
        uint32 reserveRatio; // Ratio for the bonding curve
        mapping(address => uint256) curatorShares; // Mapping of curator => shares
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

    // Address of the staking contract that will distribute fees to reserves
    address public staking;

    // Token used for staking
    IGraphToken public token;

    // Mapping of subgraphDeploymentID => CurationPool
    // There is only one CurationPool per SubgraphDeployment
    mapping(bytes32 => CurationPool) public pools;
}
