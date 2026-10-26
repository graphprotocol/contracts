// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IBridgeMockLike {
    function setInbox(address inbox, bool enabled) external;

    function setOutbox(address outbox, bool enabled) external;
}

interface IInboxMockLike {
    event InboxMessageDelivered(uint256 indexed messageNum, bytes data);

    function setBridge(address bridge) external;
}

interface IOutboxMockLike {
    function setBridge(address bridge) external;

    function executeTransaction(
        uint256 batchNum,
        bytes32[] calldata proof,
        uint256 index,
        address l2Sender,
        address destAddr,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        uint256 amount,
        bytes calldata calldataForL1
    ) external;
}

interface ICallhookReceiverMockLike {
    event TransferReceived(address from, uint256 amount, uint256 foo, uint256 bar);
}
