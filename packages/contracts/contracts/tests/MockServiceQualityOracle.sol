// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.7.6;

import { IServiceQualityOracle } from "@graphprotocol/common/contracts/quality/IServiceQualityOracle.sol";
import { ERC165 } from "@openzeppelin/contracts/introspection/ERC165.sol";

/**
 * @title MockServiceQualityOracle
 * @author Edge & Node
 * @notice A simple mock contract for the ServiceQualityOracle interface
 * @dev A simple mock contract for the ServiceQualityOracle interface
 */
contract MockServiceQualityOracle is IServiceQualityOracle, ERC165 {
    /// @dev Mapping to store allowed status for each indexer
    mapping(address => bool) private _allowed;

    /// @dev Mapping to track which indexers have been explicitly set
    mapping(address => bool) private _isSet;

    /// @dev Default response for indexers not explicitly set
    bool private _defaultResponse;

    /**
     * @notice Constructor
     * @param defaultResponse Default response for isAllowed
     */
    constructor(bool defaultResponse) {
        _defaultResponse = defaultResponse;
    }

    /**
     * @notice Set whether a specific indexer is allowed
     * @param indexer The indexer address
     * @param allowed Whether the indexer is allowed
     */
    function setIndexerAllowed(address indexer, bool allowed) external {
        _allowed[indexer] = allowed;
    }

    /**
     * @notice Set the default response for indexers not explicitly set
     * @param defaultResponse The default response
     */
    function setDefaultResponse(bool defaultResponse) external {
        _defaultResponse = defaultResponse;
    }

    /**
     * @inheritdoc IServiceQualityOracle
     */
    function isAllowed(address indexer) external view override returns (bool) {
        // If the indexer has been explicitly set, return that value
        if (_isSet[indexer]) {
            return _allowed[indexer];
        }

        // Otherwise return the default response
        return _defaultResponse;
    }

    /**
     * @inheritdoc ERC165
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IServiceQualityOracle).interfaceId || super.supportsInterface(interfaceId);
    }
}
