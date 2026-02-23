// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { IIssuanceAllocationDistribution } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationDistribution.sol";
import { IIssuanceAllocationAdministration } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationAdministration.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title MockReentrantTarget
 * @author Edge & Node
 * @notice A malicious mock contract that attempts reentrancy attacks for testing
 * @dev Used for testing reentrancy protection in IssuanceAllocator
 */
contract MockReentrantTarget is IIssuanceTarget, ERC165 {
    /// @notice The issuance allocator to target for reentrancy attacks
    address public issuanceAllocator;
    /// @notice The configured reentrancy action to perform
    ReentrantAction public actionToPerform;
    /// @notice Whether reentrancy should be attempted
    bool public shouldAttemptReentrancy;

    enum ReentrantAction {
        None,
        DistributeIssuance,
        SetTargetAllocation1Param,
        SetTargetAllocation2Param,
        SetTargetAllocation3Param,
        SetIssuancePerBlock,
        SetIssuancePerBlock2Param,
        NotifyTarget,
        SetDefaultTarget1Param,
        SetDefaultTarget2Param,
        DistributePendingIssuance0Param,
        DistributePendingIssuance1Param
    }

    /// @notice Sets the action to perform during reentrancy attempt
    /// @param _action The reentrancy action to configure
    function setReentrantAction(ReentrantAction _action) external {
        actionToPerform = _action;
        shouldAttemptReentrancy = _action != ReentrantAction.None;
    }

    /// @inheritdoc IIssuanceTarget
    function beforeIssuanceAllocationChange() external override {
        if (!shouldAttemptReentrancy) return;

        // Attempt reentrancy based on configured action
        if (actionToPerform == ReentrantAction.DistributeIssuance) {
            IIssuanceAllocationDistribution(issuanceAllocator).distributeIssuance();
        } else if (actionToPerform == ReentrantAction.SetTargetAllocation1Param) {
            IIssuanceAllocationAdministration(issuanceAllocator).setTargetAllocation(
                IIssuanceTarget(address(this)),
                1000
            );
        } else if (actionToPerform == ReentrantAction.SetTargetAllocation2Param) {
            IIssuanceAllocationAdministration(issuanceAllocator).setTargetAllocation(
                IIssuanceTarget(address(this)),
                1000,
                0
            );
        } else if (actionToPerform == ReentrantAction.SetTargetAllocation3Param) {
            IIssuanceAllocationAdministration(issuanceAllocator).setTargetAllocation(
                IIssuanceTarget(address(this)),
                1000,
                0,
                block.number
            );
        } else if (actionToPerform == ReentrantAction.SetIssuancePerBlock) {
            IIssuanceAllocationAdministration(issuanceAllocator).setIssuancePerBlock(1000);
        } else if (actionToPerform == ReentrantAction.SetIssuancePerBlock2Param) {
            IIssuanceAllocationAdministration(issuanceAllocator).setIssuancePerBlock(1000, block.number);
        } else if (actionToPerform == ReentrantAction.NotifyTarget) {
            IIssuanceAllocationAdministration(issuanceAllocator).notifyTarget(address(this));
        } else if (actionToPerform == ReentrantAction.SetDefaultTarget1Param) {
            IIssuanceAllocationAdministration(issuanceAllocator).setDefaultTarget(address(this));
        } else if (actionToPerform == ReentrantAction.SetDefaultTarget2Param) {
            IIssuanceAllocationAdministration(issuanceAllocator).setDefaultTarget(address(this), block.number);
        } else if (actionToPerform == ReentrantAction.DistributePendingIssuance0Param) {
            IIssuanceAllocationAdministration(issuanceAllocator).distributePendingIssuance();
        } else if (actionToPerform == ReentrantAction.DistributePendingIssuance1Param) {
            IIssuanceAllocationAdministration(issuanceAllocator).distributePendingIssuance(block.number);
        }
    }

    /// @inheritdoc IIssuanceTarget
    function setIssuanceAllocator(address _issuanceAllocator) external override {
        issuanceAllocator = _issuanceAllocator;
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IIssuanceTarget).interfaceId || super.supportsInterface(interfaceId);
    }
}
