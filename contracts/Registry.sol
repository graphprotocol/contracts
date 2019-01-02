pragma solidity ^0.5.2;

import "./Ownable.sol";

contract Registry is Owned {
    
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
    mapping (string => address) internal registeredUrls;

    /* Contract Constructor */
    constructor () public {}

    /* Graph Protocol Functions */
    /**
     * @dev Retrieve Ethereum address for given URL
     * @param _url <string> - URL mapped to desired address
     */
    function getAddressForUrl (string memory _url) public view returns (address memory);

    // WIP...
     
}