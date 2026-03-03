// SPDX-License-Identifier: GPL-2.0-or-later

// solhint-disable gas-increment-by-one, gas-indexed-events, named-parameters-mapping, use-natspec

pragma solidity ^0.7.6;
pragma abicoder v2;

import { IERC165 } from "@openzeppelin/contracts/introspection/IERC165.sol";
import { TargetIssuancePerBlock } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocatorTypes.sol";
import { IIssuanceAllocationDistribution } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationDistribution.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";

/**
 * @title MockIssuanceAllocator
 * @dev A simple mock contract for the IssuanceAllocator interfaces used by RewardsManager.
 */
contract MockIssuanceAllocator is IERC165, IIssuanceAllocationDistribution {
    /// @dev Mapping to store TargetIssuancePerBlock for each target
    mapping(address => TargetIssuancePerBlock) private _targetIssuance;

    /**
     * @dev Call beforeIssuanceAllocationChange on a target
     * @param target The target contract address
     */
    function callBeforeIssuanceAllocationChange(address target) external {
        IIssuanceTarget(target).beforeIssuanceAllocationChange();
    }

    /**
     * @inheritdoc IIssuanceAllocationDistribution
     */
    function getTargetIssuancePerBlock(address target) external view override returns (TargetIssuancePerBlock memory) {
        return _targetIssuance[target];
    }

    /**
     * @inheritdoc IIssuanceAllocationDistribution
     * @dev Mock always returns current block number
     */
    function distributeIssuance() external view override returns (uint256) {
        return block.number;
    }

    /**
     * @dev Set target issuance directly for testing
     * @param target The target contract address
     * @param allocatorIssuance The allocator issuance per block
     * @param selfIssuance The self issuance per block
     * @param callBefore Whether to call beforeIssuanceAllocationChange on the target
     */
    function setTargetAllocation(
        address target,
        uint256 allocatorIssuance,
        uint256 selfIssuance,
        bool callBefore
    ) external {
        if (callBefore) {
            IIssuanceTarget(target).beforeIssuanceAllocationChange();
        }
        _targetIssuance[target] = TargetIssuancePerBlock({
            allocatorIssuanceRate: allocatorIssuance,
            allocatorIssuanceBlockAppliedTo: block.number,
            selfIssuanceRate: selfIssuance,
            selfIssuanceBlockAppliedTo: block.number
        });
    }

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return
            interfaceId == type(IIssuanceAllocationDistribution).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}
