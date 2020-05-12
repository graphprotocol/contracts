pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "./Governed.sol";


contract ServiceRegistry is Governed {
    // -- Events --

    event ServiceRegistered(address indexed indexer, string host, string geohash);
    event ServiceUnregistered(address indexed indexer);

    /**
     * @dev Contract Constructor
     * @param _governor Address governing this contract
     */
    constructor(address _governor) public Governed(_governor) {}

    /*
     * @dev Set service provider url from their address
     * @param _url <string> - URL of the service provider
     */
    function register(string calldata _host, string calldata _geohash) external {
        emit ServiceRegistered(msg.sender, _host, _geohash);
    }

    /*
     * @dev Set service provider url from their address
     * @param _url <string> - URL of the service provider
     */
    function unregister() external {
        emit ServiceUnregistered(msg.sender);
    }
}
