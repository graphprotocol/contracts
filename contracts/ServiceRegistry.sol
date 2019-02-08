pragma solidity ^0.5.2;

import "./Governed.sol";

contract ServiceRegistry is Governed {
    
    /* 
    * @title Graph Protocol Service Registry contract
    *
    * @author Bryant Eisenbach
    * @author Reuven Etzion
    *
    * @notice Contract Specification:
    *
    * Requirements ("Service Registry" contract):
    * req 01 Maps Ethereum Addresses to URLs
    * req 02 No other contracts depend on this, rather is consumed by users of The Graph.
    * ...
    * @question - Who sets registeredUrls? Staking? (need interface)
    */

    /* STATE VARIABLES */
    // Storage of Ethereum addresses mapped to Indexing Node URLs
    mapping (address => bytes) internal registeredUrls;

    /* Contract Constructor */
    /* @param _governor <address> - Address of the multisig contract as Governor of this contract */
    constructor (address _governor) public Governed (_governor) {}

    /* Graph Protocol Functions */

    // WIP...
     
}
