pragma solidity ^0.5.2;

import "./Owned.sol";

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
    * ...
    * Version 2
    * @req 01 (V2) Change Mutli-sig to use a voting mechanism
    *   - Majority of votes after N% of votes cast will trigger proposed actions
    */

    // @FEATURE?: Add Owned contract to upgradableContracts?
    // @FEATURE?: Remove or disable ownership of Owned contract?


    /* STATE VARIABLES */
    // List of upgradable contracts to be owned by the multisig
    Owned[] public upgradableContracts;

    /**
     * @dev Governance Contract Constructor
     * @param _upgradableContracts <list> - List of addresses of deployed contracts to be owned
     * @param _initialOwner <address> - An initial owner is required; address(0x0) will default to msg.sender
     */
    constructor (Owned[] memory _upgradableContracts, address _initialOwner) public;

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
    
}