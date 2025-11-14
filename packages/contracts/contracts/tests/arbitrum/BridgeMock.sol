// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-increment-by-one, use-natspec

import { IBridge } from "@graphprotocol/interfaces/contracts/contracts/arbitrum/IBridge.sol";

/**
 * @title Arbitrum Bridge mock contract
 * @dev This contract implements Arbitrum's IBridge interface for testing purposes
 */
contract BridgeMock is IBridge {
    /**
     * @notice Address of the (mock) Arbitrum Inbox
     */
    address public inbox;
    /**
     * @notice Address of the (mock) Arbitrum Outbox
     */
    address public outbox;
    /**
     * @notice Index of the next message on the inbox messages array
     */
    uint256 public messageIndex;
    /**
     * @inheritdoc IBridge
     */
    bytes32[] public override inboxAccs;

    /**
     * @inheritdoc IBridge
     */
    function deliverMessageToInbox(
        uint8 _kind,
        address _sender,
        bytes32 _messageDataHash
    ) external payable override returns (uint256) {
        messageIndex = messageIndex + 1;
        inboxAccs.push(keccak256(abi.encodePacked(inbox, _kind, _sender, _messageDataHash)));
        emit MessageDelivered(messageIndex, inboxAccs[messageIndex - 1], msg.sender, _kind, _sender, _messageDataHash);
        return messageIndex;
    }

    /**
     * @inheritdoc IBridge
     */
    function executeCall(
        address _destAddr,
        uint256 _amount,
        bytes calldata _data
    ) external override returns (bool, bytes memory) {
        require(outbox == msg.sender, "NOT_FROM_OUTBOX");
        bool success;
        bytes memory returnData;

        // solhint-disable-next-line avoid-low-level-calls
        (success, returnData) = _destAddr.call{ value: _amount }(_data);
        emit BridgeCallTriggered(msg.sender, _destAddr, _amount, _data);
        return (success, returnData);
    }

    /**
     * @inheritdoc IBridge
     */
    function setInbox(address _inbox, bool _enabled) external override {
        inbox = _inbox;
        emit InboxToggle(inbox, _enabled);
    }

    /**
     * @inheritdoc IBridge
     */
    function setOutbox(address _outbox, bool _enabled) external override {
        outbox = _outbox;
        emit OutboxToggle(outbox, _enabled);
    }

    // View functions

    /**
     * @inheritdoc IBridge
     */
    function activeOutbox() external view override returns (address) {
        return outbox;
    }

    /**
     * @inheritdoc IBridge
     */
    function allowedInboxes(address _inbox) external view override returns (bool) {
        return _inbox == inbox;
    }

    /**
     * @inheritdoc IBridge
     */
    function allowedOutboxes(address _outbox) external view override returns (bool) {
        return _outbox == outbox;
    }

    /**
     * @inheritdoc IBridge
     */
    function messageCount() external view override returns (uint256) {
        return inboxAccs.length;
    }
}
