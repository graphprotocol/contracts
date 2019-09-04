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

    /* EVENTS */
    event ServiceUrlSet (address indexed serviceProvider, string urlString, bytes urlBytes);

    /* Contract Constructor */
    /* @param _governor <address> - Address of the multisig contract as Governor of this contract */
    constructor (address _governor) public Governed(_governor) {}

    /* STATE VARIABLES */
    // Storage of a hashed top level domain to owners
    mapping(address => bytes) public urls;

    /* Graph Protocol Functions */

    /*
     * @notice Set service provider url from their address
     * @dev Only msg.sender may do this
     *
     * @param _serviceProvider <address> - Address of the service provider
     * @param _url <string> - URL of the service provider
     */
    function setUrl(address _serviceProvider, string calldata _url) external {
        require(msg.sender == _serviceProvider, "msg.sender must call");
        bytes memory url = bytes(_url);
        urls[msg.sender] = url;
        emit ServiceUrlSet(_serviceProvider, _url, url);
    }
}
