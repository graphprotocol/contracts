// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.33;

/// @title MockRewardsEligibilityOracle
/// @author The Graph Contributors
/// @notice Testnet REO replacement. Indexers control their own eligibility.
/// @dev Everyone starts eligible. Call setEligible(false) to become ineligible.
contract MockRewardsEligibilityOracle {
    mapping(address indexer => bool isIneligible) private ineligible;

    /// @notice Emitted when an indexer changes their eligibility.
    /// @param indexer The indexer address.
    /// @param eligible Whether the indexer is now eligible.
    event EligibilitySet(address indexed indexer, bool indexed eligible);

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
    /// @dev Supports IRewardsEligibility (0x66e305fd) and IERC165 (0x01ffc9a7).
    /// @param interfaceId The interface identifier to check.
    /// @return True if the interface is supported.
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x66e305fd || interfaceId == 0x01ffc9a7;
    }
}
