// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { TargetIssuancePerBlock } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocatorTypes.sol";
import { IIssuanceAllocationDistribution } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationDistribution.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";

/// 0.8 port of packages/contracts/contracts/tests/MockIssuanceAllocator.sol.
contract RMIssuanceAllocatorMock is IERC165, IIssuanceAllocationDistribution {
    mapping(address target => TargetIssuancePerBlock issuance) private _targetIssuance;

    function callBeforeIssuanceAllocationChange(address target) external {
        IIssuanceTarget(target).beforeIssuanceAllocationChange();
    }

    function getTargetIssuancePerBlock(address target) external view override returns (TargetIssuancePerBlock memory) {
        return _targetIssuance[target];
    }

    /// Always returns the current block number.
    function distributeIssuance() external view override returns (uint256) {
        return block.number;
    }

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

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return
            interfaceId == type(IIssuanceAllocationDistribution).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}
