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
    mapping (address => bytes) public registeredUrls;

    /* Contract Constructor */
    /* @param _governor <address> - Address of the multisig contract as Governor of this contract */
    constructor (address _governor) public Governed (_governor)
    {
        revert();
    }

    /* Graph Protocol Functions */

    /*
     * @notice Set service provider url from their address
     * @dev Only DAO owner may do this
     *
     * @param _serviceProvider <address> - Address of the service provider
     * @param _url <bytes> - URL of the service provider
     */
    function setUrl (address _serviceProvider, bytes calldata _url) external onlyGovernance;

}
