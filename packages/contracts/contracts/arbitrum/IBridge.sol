// SPDX-License-Identifier: Apache-2.0

/*
 * Copyright 2021, Offchain Labs, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Originally copied from:
 * https://github.com/OffchainLabs/arbitrum/tree/e3a6307ad8a2dc2cad35728a2a9908cfd8dd8ef9/packages/arb-bridge-eth
 *
 * MODIFIED from Offchain Labs' implementation:
 * - Changed solidity version to 0.7.6 (pablo@edgeandnode.com)
 *
 */

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events

/**
 * @title Bridge Interface
 * @author Edge & Node
 * @notice Interface for the Arbitrum Bridge contract
 */
interface IBridge {
    /**
     * @notice Emitted when a message is delivered to the inbox
     * @param messageIndex Index of the message
     * @param beforeInboxAcc Inbox accumulator before this message
     * @param inbox Address of the inbox
     * @param kind Type of the message
     * @param sender Address that sent the message
     * @param messageDataHash Hash of the message data
     */
    event MessageDelivered(
        uint256 indexed messageIndex,
        bytes32 indexed beforeInboxAcc,
        address inbox,
        uint8 kind,
        address sender,
        bytes32 messageDataHash
    );

    /**
     * @notice Emitted when a bridge call is triggered
     * @param outbox Address of the outbox
     * @param destAddr Destination address for the call
     * @param amount ETH amount sent with the call
     * @param data Calldata for the function call
     */
    event BridgeCallTriggered(address indexed outbox, address indexed destAddr, uint256 amount, bytes data);

    /**
     * @notice Emitted when an inbox is enabled or disabled
     * @param inbox Address of the inbox
     * @param enabled Whether the inbox is enabled
     */
    event InboxToggle(address indexed inbox, bool enabled);

    /**
     * @notice Emitted when an outbox is enabled or disabled
     * @param outbox Address of the outbox
     * @param enabled Whether the outbox is enabled
     */
    event OutboxToggle(address indexed outbox, bool enabled);

    /**
     * @notice Deliver a message to the inbox
     * @param kind Type of the message
     * @param sender Address that is sending the message
     * @param messageDataHash keccak256 hash of the message data
     * @return The message index
     */
    function deliverMessageToInbox(
        uint8 kind,
        address sender,
        bytes32 messageDataHash
    ) external payable returns (uint256);

    /**
     * @notice Execute a call from L2 to L1
     * @param destAddr Contract to call
     * @param amount ETH value to send
     * @param data Calldata for the function call
     * @return success True if the call was successful, false otherwise
     * @return returnData Return data from the call
     */
    function executeCall(
        address destAddr,
        uint256 amount,
        bytes calldata data
    ) external returns (bool success, bytes memory returnData);

    /**
     * @notice Set the address of an inbox
     * @param inbox Address of the inbox
     * @param enabled Whether to enable the inbox
     */
    function setInbox(address inbox, bool enabled) external;

    /**
     * @notice Set the address of an outbox
     * @param inbox Address of the outbox
     * @param enabled Whether to enable the outbox
     */
    function setOutbox(address inbox, bool enabled) external;

    // View functions

    /**
     * @notice Get the active outbox address
     * @return The active outbox address
     */
    function activeOutbox() external view returns (address);

    /**
     * @notice Check if an address is an allowed inbox
     * @param inbox Address to check
     * @return True if the address is an allowed inbox, false otherwise
     */
    function allowedInboxes(address inbox) external view returns (bool);

    /**
     * @notice Check if an address is an allowed outbox
     * @param outbox Address to check
     * @return True if the address is an allowed outbox, false otherwise
     */
    function allowedOutboxes(address outbox) external view returns (bool);

    /**
     * @notice Get the inbox accumulator at a specific index
     * @param index Index to query
     * @return The inbox accumulator at the given index
     */
    function inboxAccs(uint256 index) external view returns (bytes32);

    /**
     * @notice Get the count of messages in the inbox
     * @return Number of messages in the inbox
     */
    function messageCount() external view returns (uint256);
}
