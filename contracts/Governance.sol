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
    * @req 01 (V1) Contract has an owner/admin (Mutli-sig will be the owner)
    * @req 02 (V2) no Mutli-sig. Use a voting mechanism
    * @req 03 Owner can change minimumCurationStakingAmount in Staking contract 
    * @req 04 Owner can change minimumIndexingStakingAmount in Staking contract 
    * @req 05 Owner can change maxIndexers in Staking contract 
    * @req 06 Verify the goverance contract can upgrade itself to a second copy of the goverance contract (???)
    * ...
    */

    Owned[] internal governedContracts; // list of addresses of deployed contracts to be owned

    constructor (Owned[] _governed) {
        governed = _governed;
    }

    function acceptOwnership () {
        // iterate through the governed contracts and accept ownership (acceptOwnership)
    }

    function transferOwnership (address newGoverner) {
        // iterate through governed contracts and transfer to the newGoverner
    }
}