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

    struct ServiceProvider {
        address indexer;
        bytes url;
    }

    /* Contract Constructor */
    /* @param _governor <address> - Address of the multisig contract as Governor of this contract */
    constructor (address _governor) public Governed(_governor) {}

    /*  A dynamic array of URLs that bootstrap the graph subgraph
        Note: The graph subgraph bootstraps the network. It has no way to retrieve
        the list of all indexers at the start of indexing. Therefore a single
        dynamic array graphNetworkServiceProviderURLs is used to store the URLS of the Graph
        Network indexing nodes for the query node to obtain */

    // TODO - Who should be able to set this? Right now it is only governance. It needed to more robust, and we need to consider the out of protocol coordination
    ServiceProvider[] public graphNetworkServiceProviderURLs;

    /* Graph Protocol Functions */

    /*
     * @notice Set graph network subgraph indexer URLs
     * @dev Only governance can do this. Indexers added are arranged out of protocol
     *
     * @param _indexer <address> - Address of the indexer
     * @param _url <string> - URL of the service provider
     */
    function setGraphNetworkServiceProviderURLs(address _indexer, string calldata _url) external onlyGovernance {
        bytes memory url = bytes(_url);
        ServiceProvider memory serviceProvider = ServiceProvider(_indexer, url);
        (bool found, uint256 index) = findURLIndex(_indexer);
        if (found == false) {
            graphNetworkServiceProviderURLs.push(serviceProvider);
        } else {
            // To update the URL
            graphNetworkServiceProviderURLs[index] = serviceProvider;
        }
        emit ServiceUrlSet(_indexer, _url, url);
    }

    /*
     * @notice Remove graph network subgraph indexer URLs
     * @dev Only governance can do this. Indexers removed when they stop indexing
     *
     * @param _indexer <address> - Address of the indexer
     */
    function removeGraphNetworkIndexerURL(address _indexer) external onlyGovernance {
        (bool found, uint256 userIndex) = findURLIndex(msg.sender);
        require(found == true, "This address is not a graph subgraph indexer. This error should never occur.");
        // Note, this does not decrease the length of the array, it just sets this index to 0x000...
        delete graphNetworkServiceProviderURLs[userIndex];
    }

    /*
     * @notice Set service provider url from their address
     * @dev Only msg.sender may do this
     *
     * @param _indexer <address> - Address of the service provider
     * @param _url <string> - URL of the service provider
     */
    function setUrl(address _indexer, string calldata _url) external {
        require(msg.sender == _indexer, "msg.sender must call");
        bytes memory url = bytes(_url);
        emit ServiceUrlSet(_indexer, _url, url);
    }
    /**
     * @dev A function to help find the location of the indexer URL in the dynamic array. Note that
            it must return a bool if the value was found, because an index of 0 can be literally the
            index of 0, or else it refers to an address that was not found.
     * @param _indexer <address> - The address of the indexer to look up.
    */
    function findURLIndex(address _indexer)
    private
    view
    returns (bool found, uint256 userIndex)  {
        // We must find the indexers location in the array first
        for (uint256 i; i < graphNetworkServiceProviderURLs.length; i++) {
            if (graphNetworkServiceProviderURLs[i].indexer == _indexer) {
                userIndex = i;
                found = true;
                break;
            }
        }
    }
    /**
     * @dev Get the number of index URLs in the dynamic array
     */
    function numberOfGraphNetworkServiceProviderURLs() public view returns (uint count) {
        return graphNetworkServiceProviderURLs.length;
    }

}

