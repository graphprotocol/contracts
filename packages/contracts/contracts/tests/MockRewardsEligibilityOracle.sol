// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.7.6;

import { IRewardsEligibilityOracle } from "@graphprotocol/common/contracts/quality/IRewardsEligibilityOracle.sol";
import { ERC165 } from "@openzeppelin/contracts/introspection/ERC165.sol";

/**
 * @title MockRewardsEligibilityOracle
 * @author Edge & Node
 * @notice A simple mock contract for the RewardsEligibilityOracle interface
 * @dev A simple mock contract for the RewardsEligibilityOracle interface
 */
contract MockRewardsEligibilityOracle is IRewardsEligibilityOracle, ERC165 {
    /// @dev Mapping to store eligibility status for each indexer
    mapping(address => bool) private _eligible;

    /// @dev Mapping to track which indexers have been explicitly set
    mapping(address => bool) private _isSet;

    /// @dev Default response for indexers not explicitly set
    bool private _defaultResponse;

    /**
     * @notice Constructor
     * @param defaultResponse Default response for isEligible
     */
    constructor(bool defaultResponse) {
        _defaultResponse = defaultResponse;
    }

    /**
     * @notice Set whether a specific indexer is eligible
     * @param indexer The indexer address
     * @param eligible Whether the indexer is eligible
     */
    function setIndexerEligible(address indexer, bool eligible) external {
        _eligible[indexer] = eligible;
        _isSet[indexer] = true;
    }

    /**
     * @notice Set the default response for indexers not explicitly set
     * @param defaultResponse The default response
     */
    function setDefaultResponse(bool defaultResponse) external {
        _defaultResponse = defaultResponse;
    }

    /**
     * @inheritdoc IRewardsEligibilityOracle
     */
    function isEligible(address indexer) external view override returns (bool) {
        // If the indexer has been explicitly set, return that value
        if (_isSet[indexer]) {
            return _eligible[indexer];
        }

        // Otherwise return the default response
        return _defaultResponse;
    }

    /**
     * @inheritdoc ERC165
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IRewardsEligibilityOracle).interfaceId || super.supportsInterface(interfaceId);
    }
}
