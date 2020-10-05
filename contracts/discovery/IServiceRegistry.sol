pragma solidity ^0.6.12;

interface IServiceRegistry {
    struct IndexerService {
        string url;
        string geohash;
    }

    function register(string calldata _url, string calldata _geohash) external;

    function unregister() external;

    function isRegistered(address _indexer) external view returns (bool);
}
