// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title IRewardsManagerDeprecated
 * @author Edge & Node
 * @notice Deprecated methods for the RewardsManager contract.
 * @dev This interface collects functions that exist on the deployed contract but are superseded
 * by newer alternatives on {IRewardsManager}. It includes raw storage getters, legacy setters,
 * and older computed getters whose behaviour may not reflect current protocol semantics.
 * The behaviour of these functions may change in future protocol upgrades and should not be
 * relied upon. New and upgraded integrations should use {IRewardsManager} instead.
 *
 * This interface does not aim to cover every deprecated function on the contract — only those
 * for which existing code has a concrete dependency. Additional deprecated functions may be
 * added in future as needed.
 */
interface IRewardsManagerDeprecated {
    /**
     * @notice Deprecated: Get the issuance rate per block
     * @dev Currently returns the raw storage value which may not reflect the effective protocol
     * issuance rate. Use {IRewardsManager-getAllocatedIssuancePerBlock} instead.
     *
     * WARNING: The value returned by this function may diverge from the effective issuance rate
     * due to issuance allocation changes. When an issuance allocator is set, the effective rate is
     * determined by the allocator while this function continues to return the raw storage value.
     * @return issuanceRate Issuance rate per block
     */
    function issuancePerBlock() external view returns (uint256 issuanceRate);

    /**
     * @notice Deprecated: Set the issuance per block for rewards distribution
     * @dev Prefer using the issuance allocator via {IRewardsManager-getIssuanceAllocator} for
     * new deployments. This setter only affects the raw storage value and is ignored if an
     * issuance allocator is set.
     * @param newIssuancePerBlock Issance rate set per block
     */
    function setIssuancePerBlock(uint256 newIssuancePerBlock) external;
}
