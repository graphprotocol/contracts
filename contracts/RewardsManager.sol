pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "./Governed.sol";


contract RewardsManager is Governed {
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
     * req 01 Has the ability to mint tokens according to the reward rules specified in mechanism
     *   design of technical specification.
     * req 02 Governance contract can update parameters { curatorRewardRate, targetParticipationRate, yearlyInflationRate }
     * req 03 claimRewards function
     * req 04 uint256 for yearly inflation rate
     * req 05 a mapping that records the usage in queries of each index chain ,
     * which would look like mapping( indexChainID bytes32 -> queryAmount uint256)
     */

    /* STATE VARIABLES */
    // Percentage of the total Graph Token supply
    // @dev Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public curatorRewardRate;

    // Targeted participitation reward rate
    // @dev Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public targetParticipationRate;

    // Yearly Inflation Rate
    // @dev Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public yearlyInflationRate = 100000; // 10%

    // Mapping of indexChainID to queryAmount
    mapping(bytes32 => uint256) public indexChainQueryAmounts;

    /**
     * @dev Reward Manager Contract Constructor
     * @param _governor <address> - Address of the multisig contract as Governor of this contract
     */
    constructor(address _governor) public Governed(_governor) {}

    /* Graph Protocol Functions */
    /**
     * @dev Governance contract owns this contract and can update curatorRewardRate
     * @param _newCuratorRewardRate <uint256> - New curation reward rate
     */
    function updateCuratorRewardRate(uint256 _newCuratorRewardRate)
        public
        onlyGovernor
        returns (bool success)
    {
        revert();
    }

    /**
     * @dev Governance contract owns this contract and can update targetParticipationRate
     * @param _newTargetParticipationRate <uint256> - New curation reward rate
     */
    function updateTargetParticipationRate(uint256 _newTargetParticipationRate)
        public
        onlyGovernor
        returns (bool success)
    {
        revert();
    }

    /**
     * @dev Governance contract owns this contract and can update targetParticipationRate
     * @param _newYearlyInflationRate <uint256> - New yearly inflation rate in parts per million. (999999 = 99.9999%)
     */
    function updateYearlyInflationRate(uint256 _newYearlyInflationRate)
        public
        onlyGovernor
        returns (bool success)
    {
        revert();
    }

    /**
     * @dev Governance contract owns this contract and can mint tokens based on reward calculations
     * @dev The RewardManger contract must be added as a treasurer in the GraphToken contract
     * req Calculate rewards based on local variables and call the mint function in GraphToken
     * @param _account <address> - The account that will receive the created tokens.
     * @param _value <uint256> - The amount that will be created.
     */
    function mintRewardTokens(address _account, uint256 _value)
        public
        onlyGovernor
        returns (bool success)
    {
        revert();
    }

    /**
     * @dev Validators can claim rewards or add them to their stake
     * @param _validatorId <bytes32> - ID of the validator claiming rewards
     * @param _addToStake <bool> - Send the rewards back to the validator's stake
     */
    function claimRewards(bytes32 _validatorId, bool _addToStake)
        public
        returns (uint256 rewaredAmount)
    {
        revert();
    }
}
