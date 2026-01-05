// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title MockNotificationTracker
 * @author Edge & Node
 * @notice A mock contract that tracks notification calls for testing
 * @dev Records when beforeIssuanceAllocationChange is called
 */
contract MockNotificationTracker is IIssuanceTarget, ERC165 {
    /// @notice Number of times the contract has been notified
    uint256 public notificationCount;

    /// @notice Block number of the last notification received
    uint256 public lastNotificationBlock;

    /// @notice Emitted when a notification is received
    /// @param blockNumber The block number when notification was received
    /// @param count The total notification count after this notification
    event NotificationReceived(uint256 indexed blockNumber, uint256 indexed count); // solhint-disable-line gas-indexed-events

    /// @inheritdoc IIssuanceTarget
    function beforeIssuanceAllocationChange() external override {
        ++notificationCount;
        lastNotificationBlock = block.number;
        emit NotificationReceived(block.number, notificationCount);
    }

    /// @inheritdoc IIssuanceTarget
    function setIssuanceAllocator(address _issuanceAllocator) external pure override {}

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IIssuanceTarget).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Resets the notification counter and last block to zero
    function resetNotificationCount() external {
        notificationCount = 0;
        lastNotificationBlock = 0;
    }
}
