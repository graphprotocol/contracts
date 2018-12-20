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
    * @req 02 Function to check Mutli-sig authorization
    * @req 03 Make external call to minimumCurationStakingAmount in Staking contract as Governor
    * @req 04 Make external call to minimumIndexingStakingAmount in Staking contract 
    * @req 05 Make external call to maxIndexers in Staking contract 
    * @req 06 Verify the goverance contract can upgrade itself to a second copy of the goverance contract (???)
    * ...
    * Version 2
    * @req 02 (V2) Change Mutli-sig to use a voting mechanism
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
        bool pass = false;
        for (uint i; i < governors.length; i++) {
            if (governors[i] == msg.sender) pass = true;
        }
        require(pass);
        _;
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
    function transferContractOwnership (address _newGoverner) private onlyOwner {
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
        governors.push(_newGovernor);
    }

    // Remove a governor
    function removeGovernor (address _removedGovernor) public onlyGovernor {
        // @TODO: Pop the _removedGovernor from governors
    }

}