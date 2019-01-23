pragma solidity ^0.5.2;

import "./Owned.sol";
import "./Governed.sol";

contract Governance is Owned {
    
    /* 
    * @title Graph Contract Governance contract
    *
    * @author Bryant Eisenbach
    * @author Reuven Etzion
    *
    * @notice Contract Specification:
    *
    * There are several parameters throughout this mechanism design which are set via a
    * governance process. In the v1 specification, governance will consist of a small committee
    * which enacts changes to the protocol via a multi-sig contract.
    * 
    * Requirements ("Governance" contract):
    * @req 01 Multisig contract will own this contract
    * @req 02 Verify the goverance contract can upgrade itself to a second copy of the goverance contract (???)
    *   (GovA owns contracts 1-5 and can transfer ownership of 1-5 to GovB)
    * @req 03 Define interfaces that will change certain parameters in the upgradable contracts
    * ...
    * Version 2
    * @req 01 (V2) Change Mutli-sig to use a voting mechanism
    *   - Majority of votes after N% of votes cast will trigger proposed actions
    */

    // @FEATURE?: Add Governed contract to upgradableContracts?
    // @FEATURE?: Remove or disable ownership of Governed contract?


    /* STATE VARIABLES */
    // List of upgradable contracts to be Governed by the Governance contract owned by the multisig
    Governed[] public upgradableContracts;

    /**
     * @dev Governance Contract Constructor
     * @param _upgradableContracts <list> - List of addresses of deployed contracts to be Governed
     * @param _initialOwner <address> - An initial owner is required; address(0x0) will default to msg.sender
     */
    constructor (Governed[] memory _upgradableContracts, address _initialOwner) public;

    /* Graph Protocol Functions */
    /**
     * @dev Accept the transfer of ownership of the contracts in the upgradableContracts list
     */
    function acceptOwnershipOfAllContracts () public;

    /**
     * @dev Initiate transferring ownership of the upgradable contracts to a new Governance contract
     * @param _newGovernanceContract <address> - Address ownership will be transferred to
     */
    function transferOwnershipOfAllContracts (address _newGovernanceContract) public;

    
    /************************************************************************
    *** The following interfaces will call onlyExecutor functions in the upgradable contracts
    ************************************************************************/
    
    /**
     * @dev Call GraphToken contract to mint Graph Tokens
     * @req Governance contract must first be added as a treasurer in the GraphToken contract
     * @param account <address> - The account that will receive the created tokens.
     * @param value <uint256> - The amount that will be created.
     */
    function mintGraphTokens (address _account, uint256 _value) public onlyOwner returns (bool success);

    /**
     * @dev Call RewardsManager contract to update curatorRewardRate
     * @param _newCuratorRewardRate <uint128> - New curation reward rate
     */
    function updateCuratorRewardRate (uint128 _newCuratorRewardRate) public onlyOwner returns (bool success);

    /**
     * @dev Call RewardsManager contract to update targetParticipationRate
     * @param _newTargetParticipationRate <uint128> - New curation reward rate
     */
    function updateTargetParticipationRate (uint128 _newTargetParticipationRate) public onlyOwner returns (bool success);

    /**
     * @dev Call RewardsManager contract to mint tokens based on reward calculations
     * @req Call mintRewardTokens function in RewardsManager contract
     * @param account <address> - The account that will receive the created tokens.
     * @param value <uint256> - The amount that will be created.
     */
    function mintRewardTokens (address _account, uint256 _value) public onlyOwner returns (bool success);

    /**
     * @dev Call RewardsManager contract to update yearlyInflationRate
     * @req Call updateYearlyInflationRate function in RewardsManager contract
     * @param _newYearlyInflationRate <uint256> - New yearly inflation rate in parts per million. (999999 = 99.9999%)
     */
    function updateYearlyInflationRate (uint256 _newYearlyInflationRate) public onlyOwner returns (bool success);

    /**
     * @dev Call Staking contract to update minimumCurationStakingAmount
     * @param _minimumCurationStakingAmount <uint256> - Minimum amount allowed to be staked for Curation
     */
    function setMinimumCurationStakingAmount (uint256 _minimumCurationStakingAmount) public onlyOwner returns (bool success);

    /**
     * @dev Call Staking contract to update minimumIndexingStakingAmount
     * @param _minimumIndexingStakingAmount <uint256> - Minimum amount allowed to be staked for Indexing Nodes
     */
    function setMinimumIndexingStakingAmount (uint256 _minimumIndexingStakingAmount) public onlyOwner returns (bool success);

    /**
     * @dev Call Staking contract to update maxIndexers
     * @param _maximumIndexers <uint256> - Maximum number of Indexing Nodes allowed
     */
    function setMaximumIndexers (uint256 _maximumIndexers) public onlyOwner returns (bool success);

    /**
     * @dev Call DisputeManager contract to set arbitrator
     * @param _newArbitrator <address> - Address of the new Arbitrator
     */
    function setArbitrator (address _newArbitrator) public onlyOwner returns (bool success);

    /**
     * @dev Call DisputeManager contract to update slashingPercent
     * @param _slashingPercent <uint256> - Slashing percent
     */
    function updateSlashingPercentage (uint256 _slashingPercent) public onlyOwner returns (bool success);

}