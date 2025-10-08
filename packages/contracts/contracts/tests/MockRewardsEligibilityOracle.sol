// SPDX-License-Identifier: GPL-2.0-or-later

// solhint-disable named-parameters-mapping

pragma solidity 0.7.6;

import { IRewardsEligibilityOracle } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibilityOracle.sol";
import { ERC165 } from "@openzeppelin/contracts/introspection/ERC165.sol";

/**
 * @title MockRewardsEligibilityOracle
 * @author Edge & Node
 * @notice A simple mock contract for the RewardsEligibilityOracle interface
 * @dev A simple mock contract for the RewardsEligibilityOracle interface
 */
contract MockRewardsEligibilityOracle is IRewardsEligibilityOracle, ERC165 {
    /// @dev Mapping to store eligibility status for each indexer
    mapping(address => bool) private eligible;

    /// @dev Mapping to track which indexers have been explicitly set
    mapping(address => bool) private isSet;

    /// @dev Default response for indexers not explicitly set
    bool private defaultResponse;

    /**
     * @notice Constructor
     * @param newDefaultResponse Default response for isEligible
     */
    constructor(bool newDefaultResponse) {
        defaultResponse = newDefaultResponse;
    }

    /**
     * @notice Set whether a specific indexer is eligible
     * @param indexer The indexer address
     * @param eligibility Whether the indexer is eligible
     */
    function setIndexerEligible(address indexer, bool eligibility) external {
        eligible[indexer] = eligibility;
        isSet[indexer] = true;
    }

    /**
     * @notice Set the default response for indexers not explicitly set
     * @param newDefaultResponse The default response
     */
    function setDefaultResponse(bool newDefaultResponse) external {
        defaultResponse = newDefaultResponse;
    }

    /**
     * @inheritdoc IRewardsEligibilityOracle
     */
    function isEligible(address indexer) external view override returns (bool) {
        // If the indexer has been explicitly set, return that value
        if (isSet[indexer]) {
            return eligible[indexer];
        }

        // Otherwise return the default response
        return defaultResponse;
    }

    /**
     * @inheritdoc ERC165
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IRewardsEligibilityOracle).interfaceId || super.supportsInterface(interfaceId);
    }
}
