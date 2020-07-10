pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "./governance/Governed.sol";

contract RewardsManager is Governed {
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
