// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.27;

import { IRewardsEligibilityHelper } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibilityHelper.sol";
import { IRewardsEligibilityMaintenance } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibilityMaintenance.sol";
import { IRewardsEligibilityStatus } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibilityStatus.sol";

/**
 * @title RewardsEligibilityHelper
 * @author Edge & Node
 * @notice Stateless, permissionless convenience contract for {RewardsEligibilityOracle}.
 * Provides batch removal of expired indexers from the tracked set.
 * Independently deployable — better versions can be deployed without protocol changes.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract RewardsEligibilityHelper is IRewardsEligibilityHelper {
    /// @notice The RewardsEligibilityOracle contract address
    address public immutable ORACLE;

    /// @notice Thrown when an address parameter is the zero address
    error ZeroAddress();

    /**
     * @notice Constructor for the RewardsEligibilityHelper contract
     * @param oracle Address of the RewardsEligibilityOracle contract
     */
    constructor(address oracle) {
        require(oracle != address(0), ZeroAddress());
        ORACLE = oracle;
    }

    /// @inheritdoc IRewardsEligibilityHelper
    function removeExpiredIndexers(address[] calldata indexers) external returns (uint256 gone) {
        for (uint256 i = 0; i < indexers.length; ++i)
            if (IRewardsEligibilityMaintenance(ORACLE).removeExpiredIndexer(indexers[i])) ++gone;
    }

    /// @inheritdoc IRewardsEligibilityHelper
    function removeExpiredIndexers() external returns (uint256 gone) {
        address[] memory indexers = IRewardsEligibilityStatus(ORACLE).getIndexers();
        for (uint256 i = 0; i < indexers.length; ++i)
            if (IRewardsEligibilityMaintenance(ORACLE).removeExpiredIndexer(indexers[i])) ++gone;
    }

    /// @inheritdoc IRewardsEligibilityHelper
    function removeExpiredIndexers(uint256 offset, uint256 count) external returns (uint256 gone) {
        address[] memory indexers = IRewardsEligibilityStatus(ORACLE).getIndexers(offset, count);
        for (uint256 i = 0; i < indexers.length; ++i)
            if (IRewardsEligibilityMaintenance(ORACLE).removeExpiredIndexer(indexers[i])) ++gone;
    }
}
