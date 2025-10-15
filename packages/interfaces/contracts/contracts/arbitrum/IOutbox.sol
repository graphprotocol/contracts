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

pragma solidity ^0.7.6 || 0.8.27;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events

/**
 * @title Arbitrum Outbox Interface
 * @author Edge & Node
 * @notice Interface for the Arbitrum outbox contract
 */
interface IOutbox {
    /**
     * @notice Emitted when an outbox entry is created
     * @param batchNum Batch number
     * @param outboxEntryIndex Index of the outbox entry
     * @param outputRoot Output root hash
     * @param numInBatch Number of messages in the batch
     */
    event OutboxEntryCreated(
        uint256 indexed batchNum,
        uint256 outboxEntryIndex,
        bytes32 outputRoot,
        uint256 numInBatch
    );

    /**
     * @notice Emitted when an outbox transaction is executed
     * @param destAddr Destination address
     * @param l2Sender L2 sender address
     * @param outboxEntryIndex Index of the outbox entry
     * @param transactionIndex Index of the transaction
     */
    event OutBoxTransactionExecuted(
        address indexed destAddr,
        address indexed l2Sender,
        uint256 indexed outboxEntryIndex,
        uint256 transactionIndex
    );

    /**
     * @notice Get the L2 to L1 sender address
     * @return The sender address
     */
    function l2ToL1Sender() external view returns (address);

    /**
     * @notice Get the L2 to L1 block number
     * @return The block number
     */
    function l2ToL1Block() external view returns (uint256);

    /**
     * @notice Get the L2 to L1 Ethereum block number
     * @return The Ethereum block number
     */
    function l2ToL1EthBlock() external view returns (uint256);

    /**
     * @notice Get the L2 to L1 timestamp
     * @return The timestamp
     */
    function l2ToL1Timestamp() external view returns (uint256);

    /**
     * @notice Get the L2 to L1 batch number
     * @return The batch number
     */
    function l2ToL1BatchNum() external view returns (uint256);

    /**
     * @notice Get the L2 to L1 output ID
     * @return The output ID
     */
    function l2ToL1OutputId() external view returns (bytes32);

    /**
     * @notice Process outgoing messages
     * @param sendsData Encoded message data
     * @param sendLengths Array of message lengths
     */
    function processOutgoingMessages(bytes calldata sendsData, uint256[] calldata sendLengths) external;

    /**
     * @notice Check if an outbox entry exists
     * @param batchNum Batch number to check
     * @return True if the entry exists
     */
    function outboxEntryExists(uint256 batchNum) external view returns (bool);
}
