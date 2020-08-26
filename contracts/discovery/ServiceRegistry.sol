pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

/**
 * @title ServiceRegistry contract
 * @dev This contract supports the service discovery process by allowing indexers to
 * register their service url and any other relevant information.
 */
contract ServiceRegistry {
    // -- State --

    struct IndexerService {
        string url;
        string geohash;
    }

    mapping(address => IndexerService) public services;

    // -- Events --

    event ServiceRegistered(address indexed indexer, string url, string geohash);
    event ServiceUnregistered(address indexed indexer);

    /**
     * @dev Register an indexer service
     * @param _url URL of the indexer service
     * @param _geohash Geohash of the indexer service location
     */
    function register(string calldata _url, string calldata _geohash) external {
        address indexer = msg.sender;
        require(bytes(_url).length > 0, "Service must specify a URL");

        services[indexer] = IndexerService(_url, _geohash);

        emit ServiceRegistered(indexer, _url, _geohash);
    }

    /**
     * @dev Unregister an indexer service
     */
    function unregister() external {
        address indexer = msg.sender;
        require(isRegistered(indexer), "Service already unregistered");

        delete services[indexer];
        emit ServiceUnregistered(indexer);
    }

    /**
     * @dev Return the registration status of an indexer service
     * @return True if the indexer service is registered
     */
    function isRegistered(address _indexer) public view returns (bool) {
        return bytes(services[_indexer].url).length > 0;
    }
}
