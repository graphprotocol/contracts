// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.7.6;
pragma abicoder v2;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-increment-by-one, gas-indexed-events, gas-small-strings, use-natspec

import { ERC165 } from "@openzeppelin/contracts/introspection/ERC165.sol";
import {
    IIssuanceAllocator,
    TargetIssuancePerBlock,
    Allocation
} from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocator.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";

/**
 * @title MockIssuanceAllocator
 * @dev A simple mock contract for the IssuanceAllocator interface
 */
contract MockIssuanceAllocator is ERC165, IIssuanceAllocator {
    /// @dev The issuance rate to return
    uint256 private _issuanceRate;

    /// @dev Flag to control if the mock should revert
    bool private _shouldRevert;

    /// @dev Mapping to track allocated targets
    mapping(address => bool) private _allocatedTargets;

    /// @dev Mapping to track target allocator-minting allocations
    mapping(address => uint256) private _allocatorMintingAllocationsPPM;

    /// @dev Mapping to track target self-minting allocations
    mapping(address => uint256) private _selfMintingAllocationsPPM;

    /// @dev Array of registered targets
    address[] private _targets;

    /**
     * @dev Event emitted when callBeforeIssuanceAllocationChange is called
     * @param target The target contract address
     */
    event BeforeIssuanceAllocationChangeCalled(address target);

    /**
     * @dev Constructor
     * @param initialIssuanceRate Initial issuance rate to return
     */
    constructor(uint256 initialIssuanceRate) {
        _issuanceRate = initialIssuanceRate;
        _shouldRevert = false;
    }

    /**
     * @dev Set the issuance rate to return
     * @param issuanceRate New issuance rate
     */
    function setMockIssuanceRate(uint256 issuanceRate) external {
        _issuanceRate = issuanceRate;
    }

    /**
     * @dev Set whether the mock should revert
     * @param shouldRevert Whether to revert
     */
    function setShouldRevert(bool shouldRevert) external {
        _shouldRevert = shouldRevert;
    }

    /**
     * @dev Call beforeIssuanceAllocationChange on a target
     * @param target The target contract address
     */
    function callBeforeIssuanceAllocationChange(address target) external {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");
        IIssuanceTarget(target).beforeIssuanceAllocationChange();
        emit BeforeIssuanceAllocationChangeCalled(target);
    }

    /**
     * @inheritdoc IIssuanceAllocator
     * @dev Mock always returns current block as both blockAppliedTo fields
     */
    function getTargetIssuancePerBlock(address target) external view override returns (TargetIssuancePerBlock memory) {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");

        uint256 allocatorIssuancePerBlock = 0;
        uint256 selfIssuancePerBlock = 0;

        if (_allocatedTargets[target]) {
            uint256 allocatorIssuance = (_issuanceRate * _allocatorMintingAllocationsPPM[target]) / 1000000; // PPM conversion
            uint256 selfIssuance = (_issuanceRate * _selfMintingAllocationsPPM[target]) / 1000000; // PPM conversion
            allocatorIssuancePerBlock = allocatorIssuance;
            selfIssuancePerBlock = selfIssuance;
        }

        return
            TargetIssuancePerBlock({
                allocatorIssuancePerBlock: allocatorIssuancePerBlock,
                allocatorIssuanceBlockAppliedTo: block.number,
                selfIssuancePerBlock: selfIssuancePerBlock,
                selfIssuanceBlockAppliedTo: block.number
            });
    }

    /**
     * @inheritdoc IIssuanceAllocator
     * @dev Mock always returns current block number
     */
    function distributeIssuance() external view override returns (uint256) {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");
        return block.number;
    }

    /**
     * @inheritdoc IIssuanceAllocator
     * @dev Mock always returns true
     */
    function setIssuancePerBlock(uint256 _issuancePerBlock, bool /* _forced */) external override returns (bool) {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");
        _issuanceRate = _issuancePerBlock;
        return true;
    }

    /**
     * @inheritdoc IIssuanceAllocator
     * @dev Mock implementation that notifies target and returns true
     */
    function notifyTarget(address target) external override returns (bool) {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");
        if (_allocatedTargets[target]) {
            IIssuanceTarget(target).beforeIssuanceAllocationChange();
        }
        return true;
    }

    /**
     * @inheritdoc IIssuanceAllocator
     * @dev Mock implementation that forces notification and returns current block
     */
    function forceTargetNoChangeNotificationBlock(
        address target,
        uint256 blockNumber
    ) external override returns (uint256) {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");
        if (_allocatedTargets[target]) {
            IIssuanceTarget(target).beforeIssuanceAllocationChange();
        }
        return blockNumber;
    }

    /**
     * @inheritdoc IIssuanceAllocator
     * @dev Mock implementation that returns target at index
     */
    function getTargetAt(uint256 index) external view override returns (address) {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");
        require(index < _targets.length, "Index out of bounds");
        return _targets[index];
    }

    /**
     * @inheritdoc IIssuanceAllocator
     * @dev Mock implementation that returns target count
     */
    function getTargetCount() external view override returns (uint256) {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");
        return _targets.length;
    }

    /**
     * @inheritdoc IIssuanceAllocator
     * @dev Mock overloaded function that sets selfMinting to 0 and force to false
     */
    function setTargetAllocation(address target, uint256 allocatorMinting) external override returns (bool) {
        return _setTargetAllocation(target, allocatorMinting, 0);
    }

    /**
     * @inheritdoc IIssuanceAllocator
     * @dev Mock overloaded function that sets force to false
     */
    function setTargetAllocation(
        address target,
        uint256 allocatorMinting,
        uint256 selfMinting
    ) external override returns (bool) {
        return _setTargetAllocation(target, allocatorMinting, selfMinting);
    }

    /**
     * @inheritdoc IIssuanceAllocator
     * @dev Mock always returns true
     */
    function setTargetAllocation(
        address target,
        uint256 allocatorMinting,
        uint256 selfMinting,
        bool /* force */
    ) external override returns (bool) {
        return _setTargetAllocation(target, allocatorMinting, selfMinting);
    }

    /**
     * @dev Internal implementation for setting target allocation
     * @param target The target contract address
     * @param allocatorMinting The allocator minting allocation
     * @param selfMinting The self minting allocation
     * @return true if successful
     */
    function _setTargetAllocation(
        address target,
        uint256 allocatorMinting,
        uint256 selfMinting
    ) internal returns (bool) {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");

        uint256 totalAllocation = allocatorMinting + selfMinting;
        if (totalAllocation == 0) {
            // Remove target
            if (_allocatedTargets[target]) {
                _allocatedTargets[target] = false;
                _allocatorMintingAllocationsPPM[target] = 0;
                _selfMintingAllocationsPPM[target] = 0;
            }
        } else {
            // Add or update target
            if (!_allocatedTargets[target]) {
                _allocatedTargets[target] = true;
                _targets.push(target);
            }
            _allocatorMintingAllocationsPPM[target] = allocatorMinting;
            _selfMintingAllocationsPPM[target] = selfMinting;
        }
        return true;
    }

    /**
     * @inheritdoc IIssuanceAllocator
     */
    function getTargetAllocation(address _target) external view override returns (Allocation memory) {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");
        uint256 allocatorMintingPPM = _allocatorMintingAllocationsPPM[_target];
        uint256 selfMintingPPM = _selfMintingAllocationsPPM[_target];
        return
            Allocation({
                totalAllocationPPM: allocatorMintingPPM + selfMintingPPM,
                allocatorMintingPPM: allocatorMintingPPM,
                selfMintingPPM: selfMintingPPM
            });
    }

    /**
     * @inheritdoc IIssuanceAllocator
     */
    function getTotalAllocation() external view override returns (Allocation memory) {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");
        uint256 totalAllocatorMintingPPM = 0;
        uint256 totalSelfMintingPPM = 0;

        for (uint256 i = 0; i < _targets.length; i++) {
            address target = _targets[i];
            if (_allocatedTargets[target]) {
                totalAllocatorMintingPPM += _allocatorMintingAllocationsPPM[target];
                totalSelfMintingPPM += _selfMintingAllocationsPPM[target];
            }
        }

        return
            Allocation({
                totalAllocationPPM: totalAllocatorMintingPPM + totalSelfMintingPPM,
                allocatorMintingPPM: totalAllocatorMintingPPM,
                selfMintingPPM: totalSelfMintingPPM
            });
    }

    /**
     * @inheritdoc IIssuanceAllocator
     */
    function getTargets() external view override returns (address[] memory) {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");
        return _targets;
    }

    /**
     * @inheritdoc IIssuanceAllocator
     */
    function issuancePerBlock() external view override returns (uint256) {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");
        return _issuanceRate;
    }

    /**
     * @inheritdoc IIssuanceAllocator
     * @dev Mock returns current block
     */
    function lastIssuanceDistributionBlock() external view override returns (uint256) {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");
        return block.number;
    }

    /**
     * @inheritdoc IIssuanceAllocator
     * @dev Mock returns current block
     */
    function lastIssuanceAccumulationBlock() external view override returns (uint256) {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");
        return block.number;
    }

    /**
     * @inheritdoc IIssuanceAllocator
     * @dev Mock always returns 0
     */
    function pendingAccumulatedAllocatorIssuance() external view override returns (uint256) {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");
        return 0;
    }

    /**
     * @inheritdoc IIssuanceAllocator
     * @dev Mock always returns current block
     */
    function distributePendingIssuance() external view override returns (uint256) {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");
        return block.number;
    }

    /**
     * @inheritdoc IIssuanceAllocator
     * @dev Mock always returns current block
     */
    function distributePendingIssuance(uint256 /* toBlockNumber */) external view override returns (uint256) {
        require(!_shouldRevert, "MockIssuanceAllocator: reverted");
        return block.number;
    }

    /**
     * @inheritdoc ERC165
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IIssuanceAllocator).interfaceId || super.supportsInterface(interfaceId);
    }
}
