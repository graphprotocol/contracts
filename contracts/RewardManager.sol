pragma solidity ^0.5.2;

import "./Owned.sol";

contract RewardManager is Owned {
    
    /* 
    * @title Graph Protocol Reward Manager contract
    *
    * @author Bryant Eisenbach
    * @author Reuven Etzion
    *
    * @notice Contract Specification:
    *
    * The total monetary inflation rate of Graph Tokens, over a given inflation period 
    * (more on this later), is the sum of its two constituent components:
    * inflationRate = curatorRewardRate + participationRewardRate
    *
    * As indicated in the formula above, inflation is used to reward curation of datasets 
    * and participation in the network.
    *
    * Participation Adjusted Inflation - In order to encourage Graph Token holders to 
    * participate in the network, the protocol implements a participation-adjusted inflation reward.
    *
    * Curator Inflation Reward - The curationRewardRate is defined as a percentage of the total 
    * Graph Token supply, and is set via governance. As with the participation reward, it is paid 
    * via inflation.
    * 
    * Requirements ("Reward Manager" contract):
    * @req 01 Has the ability to mint tokens according to the reward rules specified in mechanism 
    *   design of technical specification.
    * @req 02 Mutlisig contract can update parameters { curatorRewardRate, targetParticipationRate }
    */


    /* STATE VARIABLES */
    // Percentage of the total Graph Token supply
    uint128 public curatorRewardRate;

    // Targeted participitation reward rate
    uint128 public targetParticipationRate;

    /**
     * @dev Reward Manager Contract Constructor
     */
    constructor () public;

    /* Graph Protocol Functions */
    /**
     * @dev Governance contract owns this contract and can update curatorRewardRate
     * @param _newCuratorRewardRate <uint128> - New curation reward rate
     */
    function updateCuratorRewardRate (uint128 _newCuratorRewardRate) public onlyOwner;

    /**
     * @dev Governance contract owns this contract and can update targetParticipationRate
     * @param _newTargetParticipationRate <uint128> - New curation reward rate
     */
    function updateTargetParticipationRate (uint128 _newTargetParticipationRate) public onlyOwner;

    /**
     * @dev Governance contract owns this contract and can mint tokens based on reward calculations
     * @dev The RewardManger contract must be added as a treasurer in the GraphToken contract
     * @req Calculate rewards based on local variables and call the mint function in GraphToken
     * @param account <address> - The account that will receive the created tokens.
     * @param value <uint256> - The amount that will be created.
     */
    function mintRewardTokens (address _account, uint256 _value) public onlyOwner returns (bool success);
    
}