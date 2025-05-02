// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title IIssuanceAllocator
 * @notice Interface for the IssuanceAllocator contract, which is responsible for
 * allocating token issuance to different components of the protocol.
 *
 * @dev The IssuanceAllocator distinguishes between two types of targets:
 * 1. Self-minting contracts: These can mint tokens themselves and are supported
 *    primarily for backwards compatibility with existing RewardsManager contract.
 * 2. Non-self-minting contracts: These cannot mint tokens themselves and rely on
 *    the IssuanceAllocator to mint tokens for them.
 */
interface IIssuanceAllocator {
    /**
     * @notice Distribute issuance to all active targets.
     */
    function distributeIssuance() external;

    /**
     * @notice Set the issuance per block.
     * @param _issuancePerBlock New issuance per block
     */
    function setIssuancePerBlock(uint256 _issuancePerBlock) external;

    /**
     * @notice Add a new allocation target with zero proportion.
     * @param _target Address of the target contract
     * @param _isSelfMinter Whether the target is a self-minting contract
     *
     * @dev The _isSelfMinter parameter should typically be set to false for new targets.
     * It should only be set to true for backwards compatibility with existing contracts
     * like the RewardsManager that already have minting capabilities.
     */
    function addAllocationTarget(address _target, bool _isSelfMinter) external;

    /**
     * @notice Remove an allocation target.
     * @param _target Address of the target to remove
     */
    function removeAllocationTarget(address _target) external;

    /**
     * @notice Set the allocation for a target.
     * @param _target Address of the target to update
     * @param _allocation Allocation for the target (in PPM)
     */
    function setTargetAllocation(address _target, uint256 _allocation) external;

    /**
     * @notice Get the current allocation for a target.
     * @param _target Address of the target
     * @return Allocation for the target (in PPM), or 0 if the target is not registered
     */
    function getTargetAllocation(address _target) external view returns (uint256);

    /**
     * @notice Get all registered target addresses (including those with 0 allocation).
     * @return Array of registered target addresses
     */
    function getRegisteredTargets() external view returns (address[] memory);

    /**
     * @notice Calculate the issuance per block for a specific target.
     * @param _target Address of the target
     * @return Amount of tokens issued per block for the target, or 0 if the target is not registered
     */
    function getTargetIssuancePerBlock(address _target) external view returns (uint256);

    /**
     * @notice Check if a target is a self-minting contract.
     * @param _target Address of the target
     * @return True if the target is a registered self-minting contract, false otherwise
     *
     * @dev Self-minting targets are a special case for backwards compatibility with
     * existing contracts like the RewardsManager. The IssuanceAllocator calculates
     * issuance for these targets but does not mint tokens directly to them.
     */
    function isSelfMinter(address _target) external view returns (bool);
}
