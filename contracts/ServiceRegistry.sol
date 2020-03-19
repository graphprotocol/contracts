pragma solidity ^0.6.4;

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
    event ServiceUrlSet(address indexed serviceProvider, string urlString);

    /* Contract Constructor */
    /* @param _governor <address> - Address of the multisig contract as Governor of this contract */
    constructor(address _governor) public Governed(_governor) {}

    /*  A dynamic array of URLs that bootstrap the graph subgraph
        Note: The graph subgraph bootstraps the network. It has no way to retrieve
        the list of all indexers at the start of indexing. Therefore a single
        dynamic array bootstrapIndexerURLs is used to store the URLS of the Graph
        Network indexing nodes for the query node to obtain */

    // TODO - Who should be able to set this? Right now it is only governance. It needed to more robust, and we need to consider the out of protocol coordination
    mapping(address => bytes) public bootstrapIndexerURLs;

    /* Graph Protocol Functions */

    /*
     * @notice Set graph network subgraph indexer URL
     * @dev Only governance can do this. Indexers added are arranged out of protocol
     *
     * @param _indexer <address> - Address of the indexer
     * @param _url <string> - URL of the service provider
     */
    function setBootstrapIndexerURL(address _indexer, string calldata _url)
        external
        onlyGovernance
    {
        bytes memory url = bytes(_url);
        bootstrapIndexerURLs[_indexer] = url;
        emit ServiceUrlSet(_indexer, _url);
    }

    /*
     * @notice Set service provider url from their address
     * @dev Only msg.sender may do this
     *
     * @param _url <string> - URL of the service provider
     */
    function setUrl(string calldata _url) external {
        emit ServiceUrlSet(msg.sender, _url);
    }
}
