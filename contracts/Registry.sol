pragma solidity ^0.5.2;

import "./Governed.sol";

contract Registry is Governed {
    
    /* 
    * @title Graph Protocol Service Registry contract
    *
    * @author Bryant Eisenbach
    * @author Reuven Etzion
    *
    * @notice Contract Specification:
    *
    * Requirements ("GNS" contract):
    * @req 01 Maps Ethereum Addresses to URLs
    * @req 02 No other contracts depend on this, rather is consumed by users of The Graph.
    * ...
    */

    /* STATE VARIABLES */
    // Storage of URLs mapped to Ethereum addresses
    mapping (address => bytes) internal registeredUrls;

    /* Contract Constructor */
    constructor () public;

    /* Graph Protocol Functions */
    /**
     * @dev Retrieve Ethereum address for given URL
     * @param _url <bytes> - URL mapped to desired address
     */
    function getAddressForUrl (bytes memory _url) public view returns (address);

    // WIP...
     
}