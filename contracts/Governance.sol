pragma solidity ^0.5.1;

import "./Ownable.sol";

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
    * @req 01 Multisig contract will be inheritted and own this contract
    * @req 02 Governance can update Staking contract {owner, minimumCurationStakingAmount, 
    *   minimumIndexingStakingAmount, maxIndexers}
    * @req 03 Verify the goverance contract can upgrade itself to a second copy of the goverance contract (???)
    * ...
    * Version 2
    * @req 01 (V2) Change Mutli-sig to use a voting mechanism
    *   - Contract has one or more Members, majority can vote to perform governed actions
    */

    // @TODO: multi-sig to check authorization (by vote count)?

    // @FEATURE: Add Owned contract to upgradableContracts?
    // @FEATURE: Remove or disable ownership of Owned contract?


    /* STATE VARIABLES */
    // List of governing members
    address[] private members;

    // List of addresses of upgradable contracts to be owned by the multisig
    Owned[] internal upgradableContracts;

    /* Contract Constructor */
    /* @PARAM _upgradableContracts (string) - List of addresses of deployed contracts to be owned */
    constructor (Owned[] memory _upgradableContracts) public {
        // Assign the contracts to be governed / owned
        // @DEPLOYMENT: Contracts must be deployed in the correct order
        if (_upgradableContracts.length > 0) upgradableContracts = _upgradableContracts;

        // Sender will become the sole governing member
        members.push(msg.sender);
    }

    // Member-only modifier
    modifier onlyMember {
        bool pass = false;
        for (uint i; i < members.length; i++) {
            if (members[i] == msg.sender) pass = true;
        }
        require(pass);
        _;
    }


    // Accept the transfer of ownership of the contracts in the upgradableContracts list
    function acceptOwnershipOfAllContracts () public {
        // iterate through upgradableContracts and accept ownership (acceptOwnership)
    }

    // Initiate the transfer of ownership of the contracts in the upgradableContracts list
    function transferOwnershipOfAllContracts (address _newGoverner) public onlyOwner {
        // iterate through governed contracts and transfer to the newGoverner
    }
    
    // Get list of members
    function getmembers () public view returns (address[] memory) {
        return members;
    }

    // Add a member
    function addMember (address _newMember) public onlyOwner {
        // Prevent saving a duplicate
        bool duplicate;
        for (uint i = 0; i < members.length; i++) {
            if (members[i] == _newMember) duplicate = true;
        }
        require(!duplicate);

        // Add address to members list
        members.push(_newMember);
    }

    // Remove a member
    function removeMember (address _removedMember) public onlyOwner {
        // Sender cannot remove self
        require(msg.sender != _removedMember);
        
        // Remove _removedMember from members list
        uint i = 0;
        while (members[i] != _removedMember) {
            i++;
        }
        members[i] = members[members.length - 1];
        members.length--;
    }

}