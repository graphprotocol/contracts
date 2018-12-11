pragma solidity ^0.5.0;

import "./Ownable.sol";

contract Governance is Ownable {
    
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
    * Requirements ("Governance" contract):
    * @req 01 Contract has an owner/admin
    * @req 02 Owner can change minimumStakingAmount in Staking contract 
    * @req 03 Owner can change maxIndexers in Staking contract 
    * ...
    */

}