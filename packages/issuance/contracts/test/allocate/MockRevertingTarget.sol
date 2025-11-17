// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title MockRevertingTarget
 * @author Edge & Node
 * @notice A mock contract that reverts when beforeIssuanceAllocationChange is called
 * @dev Used for testing error handling in IssuanceAllocator
 */
contract MockRevertingTarget is IIssuanceTarget, ERC165 {
    /// @notice Error thrown when the target reverts intentionally
    error TargetRevertsIntentionally();
    /**
     * @inheritdoc IIssuanceTarget
     */
    function beforeIssuanceAllocationChange() external pure override {
        revert TargetRevertsIntentionally();
    }

    /**
     * @inheritdoc IIssuanceTarget
     */
    function setIssuanceAllocator(address _issuanceAllocator) external pure override {
        // No-op
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IIssuanceTarget).interfaceId || super.supportsInterface(interfaceId);
    }
}
