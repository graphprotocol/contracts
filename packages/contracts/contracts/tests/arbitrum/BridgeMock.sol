// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "../../arbitrum/IBridge.sol";

/**
 * @title Arbitrum Bridge mock contract
 * @dev This contract implements Arbitrum's IBridge interface for testing purposes
 */
contract BridgeMock is IBridge {
    // Address of the (mock) Arbitrum Inbox
    address public inbox;
    // Address of the (mock) Arbitrum Outbox
    address public outbox;
    // Index of the next message on the inbox messages array
    uint256 public messageIndex;
    // Inbox messages array
    bytes32[] public override inboxAccs;

    /**
     * @dev Deliver a message to the inbox. The encoded message will be
     * added to the inbox array, and messageIndex will be incremented.
     * @param _kind Type of the message
     * @param _sender Address that is sending the message
     * @param _messageDataHash keccak256 hash of the message data
     * @return The next index for the inbox array
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
     * @dev Executes an L1 function call incoing from L2. This can only be called
     * by the Outbox.
     * @param _destAddr Contract to call
     * @param _amount ETH value to send
     * @param _data Calldata for the function call
     * @return True if the call was successful, false otherwise
     * @return Return data from the call
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
     * @dev Set the address of the inbox. Anyone can call this, because it's a mock.
     * @param _inbox Address of the inbox
     * @param _enabled Enable the inbox (ignored)
     */
    function setInbox(address _inbox, bool _enabled) external override {
        inbox = _inbox;
        emit InboxToggle(inbox, _enabled);
    }

    /**
     * @dev Set the address of the outbox. Anyone can call this, because it's a mock.
     * @param _outbox Address of the outbox
     * @param _enabled Enable the outbox (ignored)
     */
    function setOutbox(address _outbox, bool _enabled) external override {
        outbox = _outbox;
        emit OutboxToggle(outbox, _enabled);
    }

    // View functions

    /**
     * @dev Getter for the active outbox (in this case there's only one)
     */
    function activeOutbox() external view override returns (address) {
        return outbox;
    }

    /**
     * @dev Getter for whether an address is an allowed inbox (in this case there's only one)
     * @param _inbox Address to check
     * @return True if the address is the allowed inbox, false otherwise
     */
    function allowedInboxes(address _inbox) external view override returns (bool) {
        return _inbox == inbox;
    }

    /**
     * @dev Getter for whether an address is an allowed outbox (in this case there's only one)
     * @param _outbox Address to check
     * @return True if the address is the allowed outbox, false otherwise
     */
    function allowedOutboxes(address _outbox) external view override returns (bool) {
        return _outbox == outbox;
    }

    /**
     * @dev Getter for the count of messages in the inboxAccs
     * @return Number of messages in inboxAccs
     */
    function messageCount() external view override returns (uint256) {
        return inboxAccs.length;
    }
}
