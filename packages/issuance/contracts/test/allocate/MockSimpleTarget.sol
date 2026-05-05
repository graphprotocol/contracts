// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IIssuanceAllocationDistribution } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationDistribution.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title MockSimpleTarget
 * @author Edge & Node
 * @notice A simple mock contract that implements IIssuanceTarget for testing
 * @dev Used for testing basic functionality in IssuanceAllocator
 */
contract MockSimpleTarget is IIssuanceTarget, ERC165 {
    /// @inheritdoc IIssuanceTarget
    function beforeIssuanceAllocationChange() external pure override {}

    /// @inheritdoc IIssuanceTarget
    function getIssuanceAllocator() external pure override returns (IIssuanceAllocationDistribution) {
        return IIssuanceAllocationDistribution(address(0));
    }

    /// @inheritdoc IIssuanceTarget
    function setIssuanceAllocator(IIssuanceAllocationDistribution _issuanceAllocator) external pure override {}

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IIssuanceTarget).interfaceId || super.supportsInterface(interfaceId);
    }
}
