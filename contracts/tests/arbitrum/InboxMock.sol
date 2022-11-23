// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "../../arbitrum/IInbox.sol";
import "../../arbitrum/AddressAliasHelper.sol";

/**
 * @title Arbitrum Inbox mock contract
 * @dev This contract implements (a subset of) Arbitrum's IInbox interface for testing purposes
 */
contract InboxMock is IInbox {
    // Type indicator for a standard L2 message
    uint8 internal constant L2_MSG = 3;
    // Type indicator for a retryable ticket message
    // solhint-disable-next-line const-name-snakecase
    uint8 internal constant L1MessageType_submitRetryableTx = 9;
    // Address of the Bridge (mock) contract
    IBridge public override bridge;

    /**
     * @dev Send a message to L2 (by delivering it to the Bridge)
     * @param _messageData Encoded data to send in the message
     * @return message number returned by the inbox
     */
    function sendL2Message(bytes calldata _messageData) external override returns (uint256) {
        uint256 msgNum = deliverToBridge(L2_MSG, msg.sender, keccak256(_messageData));
        emit InboxMessageDelivered(msgNum, _messageData);
        return msgNum;
    }

    /**
     * @dev Set the address of the (mock) bridge
     * @param _bridge Address of the bridge
     */
    function setBridge(address _bridge) external {
        bridge = IBridge(_bridge);
    }

    /**
     * @dev Unimplemented in this mock
     */
    function sendUnsignedTransaction(
        uint256,
        uint256,
        uint256,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (uint256) {
        revert("Unimplemented");
    }

    /**
     * @dev Unimplemented in this mock
     */
    function sendContractTransaction(
        uint256,
        uint256,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (uint256) {
        revert("Unimplemented");
    }

    /**
     * @dev Unimplemented in this mock
     */
    function sendL1FundedUnsignedTransaction(
        uint256,
        uint256,
        uint256,
        address,
        bytes calldata
    ) external payable override returns (uint256) {
        revert("Unimplemented");
    }

    /**
     * @dev Unimplemented in this mock
     */
    function sendL1FundedContractTransaction(
        uint256,
        uint256,
        address,
        bytes calldata
    ) external payable override returns (uint256) {
        revert("Unimplemented");
    }

    /**
     * @dev Creates a retryable ticket for an L2 transaction
     * @param _destAddr Address of the contract to call in L2
     * @param _arbTxCallValue Callvalue to use in the L2 transaction
     * @param _maxSubmissionCost Max cost of submitting the ticket, in Wei
     * @param _submissionRefundAddress L2 address to refund for any remaining value from the submission cost
     * @param _valueRefundAddress L2 address to refund if the ticket times out or gets cancelled
     * @param _maxGas Max gas for the L2 transcation
     * @param _gasPriceBid Gas price bid on L2
     * @param _data Encoded calldata for the L2 transaction (including function selector)
     * @return message number returned by the bridge
     */
    function createRetryableTicket(
        address _destAddr,
        uint256 _arbTxCallValue,
        uint256 _maxSubmissionCost,
        address _submissionRefundAddress,
        address _valueRefundAddress,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data
    ) external payable override returns (uint256) {
        _submissionRefundAddress = AddressAliasHelper.applyL1ToL2Alias(_submissionRefundAddress);
        _valueRefundAddress = AddressAliasHelper.applyL1ToL2Alias(_valueRefundAddress);
        return
            _deliverMessage(
                L1MessageType_submitRetryableTx,
                msg.sender,
                abi.encodePacked(
                    uint256(uint160(bytes20(_destAddr))),
                    _arbTxCallValue,
                    msg.value,
                    _maxSubmissionCost,
                    uint256(uint160(bytes20(_submissionRefundAddress))),
                    uint256(uint160(bytes20(_valueRefundAddress))),
                    _maxGas,
                    _gasPriceBid,
                    _data.length,
                    _data
                )
            );
    }

    function depositEth(uint256) external payable override returns (uint256) {
        revert("Unimplemented");
    }

    /**
     * @dev Unimplemented in this mock
     */
    function pauseCreateRetryables() external pure override {
        revert("Unimplemented");
    }

    /**
     * @dev Unimplemented in this mock
     */
    function unpauseCreateRetryables() external pure override {
        revert("Unimplemented");
    }

    /**
     * @dev Unimplemented in this mock
     */
    function startRewriteAddress() external pure override {
        revert("Unimplemented");
    }

    /**
     * @dev Unimplemented in this mock
     */
    function stopRewriteAddress() external pure override {
        revert("Unimplemented");
    }

    /**
     * @dev Deliver a message to the bridge
     * @param _kind Type of the message
     * @param _sender Address that is sending the message
     * @param _messageData Encoded message data
     * @return Message number returned by the bridge
     */
    function _deliverMessage(
        uint8 _kind,
        address _sender,
        bytes memory _messageData
    ) internal returns (uint256) {
        uint256 msgNum = deliverToBridge(_kind, _sender, keccak256(_messageData));
        emit InboxMessageDelivered(msgNum, _messageData);
        return msgNum;
    }

    /**
     * @dev Deliver a message to the bridge
     * @param _kind Type of the message
     * @param _sender Address that is sending the message
     * @param _messageDataHash keccak256 hash of the encoded message data
     * @return Message number returned by the bridge
     */
    function deliverToBridge(
        uint8 _kind,
        address _sender,
        bytes32 _messageDataHash
    ) internal returns (uint256) {
        return bridge.deliverMessageToInbox{ value: msg.value }(_kind, _sender, _messageDataHash);
    }
}
