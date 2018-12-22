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
    // List of upgradable contracts to be owned by the multisig
    Owned[] internal upgradableContracts;

    /* Contract Constructor */
    /* @PARAM <list> _upgradableContracts - List of addresses of deployed contracts to be owned */
    constructor (Owned[] memory _upgradableContracts, address _initialOwner) public {
        // Assign the contracts to be governed / owned
        // @DEPLOYMENT: Upgradable contracts must be deployed first
        // @TODO: Parse _upgradableContracts
        if (_upgradableContracts.length > 0) upgradableContracts = _upgradableContracts;

        // Set initial owner
        if (address(_initialOwner) != address(0x0)) {owner = _initialOwner;}
        else {owner = msg.sender;} // Sender will become the owner
    }

    // Accept the transfer of ownership of the contracts in the upgradableContracts list
    function acceptOwnershipOfAllContracts () public {
        // iterate through upgradableContracts and accept ownership (acceptOwnership)
    }

    // Initiate the transfer of ownership of the contracts in the upgradableContracts list
    function transferOwnershipOfAllContracts (address _newGoverner) public onlyOwner {
        // iterate through governed contracts and transfer to the newGoverner
    }
    
}