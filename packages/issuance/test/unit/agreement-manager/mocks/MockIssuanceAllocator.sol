// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IIssuanceAllocationDistribution } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationDistribution.sol";
import { TargetIssuancePerBlock } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocatorTypes.sol";
import { MockGraphToken } from "./MockGraphToken.sol";

/// @notice Mock IssuanceAllocator that tracks distribution calls and optionally mints tokens.
contract MockIssuanceAllocator is IIssuanceAllocationDistribution, IERC165 {
    uint256 public distributeCallCount;
    uint256 public lastDistributedBlock;

    MockGraphToken public immutable graphToken;
    address public immutable target;
    uint256 public mintPerDistribution;
    bool public shouldRevert;

    constructor(MockGraphToken _graphToken, address _target) {
        graphToken = _graphToken;
        target = _target;
    }

    /// @notice Set how many tokens to mint to the target on each distribution call
    function setMintPerDistribution(uint256 amount) external {
        mintPerDistribution = amount;
    }

    /// @notice Toggle whether distributeIssuance reverts
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function distributeIssuance() external override returns (uint256) {
        require(!shouldRevert, "MockIssuanceAllocator: forced revert");
        distributeCallCount++;
        if (lastDistributedBlock == block.number) return block.number;
        lastDistributedBlock = block.number;
        if (mintPerDistribution > 0) {
            graphToken.mint(target, mintPerDistribution);
        }
        return block.number;
    }

    function getTargetIssuancePerBlock(address) external pure override returns (TargetIssuancePerBlock memory) {
        return TargetIssuancePerBlock(0, 0, 0, 0);
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return
            interfaceId == type(IIssuanceAllocationDistribution).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}
