pragma solidity ^0.5.1;

import "./Ownable.sol";

contract Governance is Owned {
    
    /* 
    * @title Graph DAO Governance contract
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
    * Requirements ("Governance"/"DAO" contract):
    * @req 01 Contract has one or more Governor(s), majority can vote to perform Governor actions
    *   - Function to check Mutli-sig authorization
    * @req 02 Make external call to minimumCurationStakingAmount in Staking contract as Governor
    * @req 03 Make external call to minimumIndexingStakingAmount in Staking contract 
    * @req 04 Make external call to maxIndexers in Staking contract 
    * @req 05 Verify the goverance contract can upgrade itself to a second copy of the goverance contract (???)
    * ...
    * Version 2
    * @req 01 (V2) Change Mutli-sig to use a voting mechanism
    *   - Contract has one or more Governor(s), majority can vote to perform Governor actions
    */

    /* STATE VARIABLES */
    // ------------------------------------------------------
    // List of governors
    address[] private governors;
    // OR...
    // Single governor
    // address private governor;
    // ------------------------------------------------------

    // List of addresses of deployed contracts to be owned
    Owned[] internal governedContracts;

    // Governor-only modifier
    modifier onlyGovernor {
        // V1 - Check that sender is a governor
        bool pass = false;
        for (uint i; i < governors.length; i++) {
            if (governors[i] == msg.sender) pass = true;
        }
        require(pass);
        _;
        // @TODO: V2 - Check concensus of all governors
    }

    constructor (Owned[] memory _governed) public {
        // Assign the contracts to be governed
        // @DEPLOYMENT: Contracts must be deployed in the correct order
        // more to come..
        if (_governed.length > 0) governedContracts = _governed;

        // Sender will become the sole governor
        governors.push(msg.sender);
    }

    // Accept the transfer of ownership of the contracts in the governedContracts list
    function acceptContractOwnership () public {
        // iterate through governedContracts and accept ownership (acceptOwnership)
    }

    // Initiate the transfer of ownership of the contracts in the governedContracts list
    function transferContractOwnership (address _newGoverner) public onlyGovernor {
        // iterate through governed contracts and transfer to the newGoverner
    }
    
    // @FEATURE: Add Owned contract to governedContracts?

    // @TODO: multi-sig function to check authorization (by vote count)?

    // Get list of governors
    function getGovernors () public view returns (address[] memory) {
        return governors;
    }

    // Add a governor
    function addGovernor (address _newGovernor) public onlyGovernor {
        // Prevent saving a duplicate
        bool duplicate;
        for (uint i = 0; i < governors.length; i++) {
            if (governors[i] == _newGovernor) duplicate = true;
        }
        require(!duplicate);

        // Add address to governors list
        governors.push(_newGovernor);
    }

    // Remove a governor
    function removeGovernor (address _removedGovernor) public onlyGovernor {
        // Sender cannot remove self
        require(msg.sender != _removedGovernor);
        
        // Remove _removedGovernor from governors list
        uint i = 0;
        while (governors[i] != _removedGovernor) {
            i++;
        }
        governors[i] = governors[governors.length - 1];
        governors.length--;
    }

}