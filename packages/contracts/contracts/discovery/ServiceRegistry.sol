// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import "../governance/Managed.sol";
import "../upgrades/GraphUpgradeable.sol";

import "./ServiceRegistryStorage.sol";
import "./IServiceRegistry.sol";

/**
 * @title ServiceRegistry contract
 * @dev This contract supports the service discovery process by allowing indexers to
 * register their service url and any other relevant information.
 */
contract ServiceRegistry is ServiceRegistryV1Storage, GraphUpgradeable, IServiceRegistry {
    // -- Events --

    event ServiceRegistered(address indexed indexer, string url, string geohash);
    event ServiceUnregistered(address indexed indexer);

    /**
     * @dev Check if the caller is authorized (indexer or operator)
     */
    function _isAuth(address _indexer) internal view returns (bool) {
        return msg.sender == _indexer || staking().isOperator(msg.sender, _indexer) == true;
    }

    /**
     * @dev Initialize this contract.
     */
    function initialize(address _controller) external onlyImpl {
        Managed._initialize(_controller);
    }

    /**
     * @dev Register an indexer service
     * @param _url URL of the indexer service
     * @param _geohash Geohash of the indexer service location
     */
    function register(string calldata _url, string calldata _geohash) external override {
        _register(msg.sender, _url, _geohash);
    }

    /**
     * @dev Register an indexer service
     * @param _indexer Address of the indexer
     * @param _url URL of the indexer service
     * @param _geohash Geohash of the indexer service location
     */
    function registerFor(
        address _indexer,
        string calldata _url,
        string calldata _geohash
    ) external override {
        _register(_indexer, _url, _geohash);
    }

    /**
     * @dev Internal: Register an indexer service
     * @param _indexer Address of the indexer
     * @param _url URL of the indexer service
     * @param _geohash Geohash of the indexer service location
     */
    function _register(
        address _indexer,
        string calldata _url,
        string calldata _geohash
    ) private {
        require(_isAuth(_indexer), "!auth");
        require(bytes(_url).length > 0, "Service must specify a URL");

        services[_indexer] = IndexerService(_url, _geohash);

        emit ServiceRegistered(_indexer, _url, _geohash);
    }

    /**
     * @dev Unregister an indexer service
     */
    function unregister() external override {
        _unregister(msg.sender);
    }

    /**
     * @dev Unregister an indexer service
     * @param _indexer Address of the indexer
     */
    function unregisterFor(address _indexer) external override {
        _unregister(_indexer);
    }

    /**
     * @dev Unregister an indexer service
     * @param _indexer Address of the indexer
     */
    function _unregister(address _indexer) private {
        require(_isAuth(_indexer), "!auth");
        require(isRegistered(_indexer), "Service already unregistered");

        delete services[_indexer];
        emit ServiceUnregistered(_indexer);
    }

    /**
     * @dev Return the registration status of an indexer service
     * @return True if the indexer service is registered
     */
    function isRegistered(address _indexer) public view override returns (bool) {
        return bytes(services[_indexer].url).length > 0;
    }
}
