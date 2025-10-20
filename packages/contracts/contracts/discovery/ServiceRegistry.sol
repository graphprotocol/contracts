// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import { Managed } from "../governance/Managed.sol";
import { GraphUpgradeable } from "../upgrades/GraphUpgradeable.sol";

import { ServiceRegistryV1Storage } from "./ServiceRegistryStorage.sol";
import { IServiceRegistry } from "@graphprotocol/interfaces/contracts/contracts/discovery/IServiceRegistry.sol";

/**
 * @title ServiceRegistry contract
 * @author Edge & Node
 * @notice This contract supports the service discovery process by allowing indexers to
 * register their service url and any other relevant information.
 */
contract ServiceRegistry is ServiceRegistryV1Storage, GraphUpgradeable, IServiceRegistry {
    // -- Events --

    /**
     * @notice Emitted when an indexer registers their service
     * @param indexer Address of the indexer
     * @param url URL of the indexer service
     * @param geohash Geohash of the indexer service location
     */
    event ServiceRegistered(address indexed indexer, string url, string geohash);

    /**
     * @notice Emitted when an indexer unregisters their service
     * @param indexer Address of the indexer
     */
    event ServiceUnregistered(address indexed indexer);

    /**
     * @notice Check if the caller is authorized (indexer or operator)
     * @param _indexer Address of the indexer to check authorization for
     * @return True if the caller is authorized, false otherwise
     */
    function _isAuth(address _indexer) internal view returns (bool) {
        return msg.sender == _indexer || staking().isOperator(msg.sender, _indexer) == true;
    }

    /**
     * @notice Initialize this contract.
     * @param _controller Address of the controller contract
     */
    function initialize(address _controller) external onlyImpl {
        Managed._initialize(_controller);
    }

    /**
     * @inheritdoc IServiceRegistry
     */
    function register(string calldata _url, string calldata _geohash) external override {
        _register(msg.sender, _url, _geohash);
    }

    /**
     * @inheritdoc IServiceRegistry
     */
    function registerFor(address _indexer, string calldata _url, string calldata _geohash) external override {
        _register(_indexer, _url, _geohash);
    }

    /**
     * @notice Internal: Register an indexer service
     * @param _indexer Address of the indexer
     * @param _url URL of the indexer service
     * @param _geohash Geohash of the indexer service location
     */
    function _register(address _indexer, string calldata _url, string calldata _geohash) private {
        require(_isAuth(_indexer), "!auth");
        require(bytes(_url).length > 0, "Service must specify a URL");

        services[_indexer] = IndexerService(_url, _geohash);

        emit ServiceRegistered(_indexer, _url, _geohash);
    }

    /**
     * @inheritdoc IServiceRegistry
     */
    function unregister() external override {
        _unregister(msg.sender);
    }

    /**
     * @inheritdoc IServiceRegistry
     */
    function unregisterFor(address _indexer) external override {
        _unregister(_indexer);
    }

    /**
     * @notice Unregister an indexer service
     * @param _indexer Address of the indexer
     */
    function _unregister(address _indexer) private {
        require(_isAuth(_indexer), "!auth");
        require(isRegistered(_indexer), "Service already unregistered");

        delete services[_indexer];
        emit ServiceUnregistered(_indexer);
    }

    /**
     * @inheritdoc IServiceRegistry
     */
    function isRegistered(address _indexer) public view override returns (bool) {
        return bytes(services[_indexer].url).length > 0;
    }
}
