// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import { BaseUpgradeable } from "../../common/BaseUpgradeable.sol";
import { IGraphToken } from "../../common/IGraphToken.sol";

/// @title MockRewardsEligibilityOracle
/// @author The Graph Contributors
/// @notice Testnet REO replacement. Indexers control their own eligibility.
/// @dev Everyone starts eligible. Call setEligible(false) to become ineligible.
/// Upgradeable via OZ TransparentUpgradeableProxy for deployment consistency.
contract MockRewardsEligibilityOracle is BaseUpgradeable {
    mapping(address indexer => bool isIneligible) private ineligible;

    /// @notice Emitted when an indexer changes their eligibility.
    /// @param indexer The indexer address.
    /// @param eligible Whether the indexer is now eligible.
    event EligibilitySet(address indexed indexer, bool indexed eligible);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IGraphToken graphToken) BaseUpgradeable(graphToken) {}

    /// @notice Initialize the contract.
    /// @param governor Address that will have the GOVERNOR_ROLE.
    function initialize(address governor) external initializer {
        __BaseUpgradeable_init(governor);
    }

    /// @notice Toggle the caller's eligibility.
    /// @param eligible True to be eligible, false to opt out.
    function setEligible(bool eligible) external {
        ineligible[msg.sender] = !eligible;
        emit EligibilitySet(msg.sender, eligible);
    }

    /// @notice Check whether an indexer is eligible for rewards.
    /// @dev Called by RewardsManager to check eligibility.
    /// @param indexer The indexer address to check.
    /// @return True if the indexer is eligible.
    function isEligible(address indexer) external view returns (bool) {
        return !ineligible[indexer];
    }

    /// @notice ERC165 interface detection.
    /// @dev Supports IRewardsEligibility (0x66e305fd) and inherited interfaces.
    /// @param interfaceId The interface identifier to check.
    /// @return True if the interface is supported.
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == 0x66e305fd || super.supportsInterface(interfaceId);
    }
}
