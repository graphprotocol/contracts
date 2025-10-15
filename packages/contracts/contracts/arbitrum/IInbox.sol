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

import { IBridge } from "./IBridge.sol";
import { IMessageProvider } from "./IMessageProvider.sol";

/**
 * @title Inbox Interface
 * @author Edge & Node
 * @notice Interface for the Arbitrum Inbox contract
 */
interface IInbox is IMessageProvider {
    /**
     * @notice Send a message to L2
     * @param messageData Encoded data to send in the message
     * @return Message number returned by the inbox
     */
    function sendL2Message(bytes calldata messageData) external returns (uint256);

    /**
     * @notice Send an unsigned transaction to L2
     * @param maxGas Maximum gas for the L2 transaction
     * @param gasPriceBid Gas price bid for the L2 transaction
     * @param nonce Nonce for the transaction
     * @param destAddr Destination address on L2
     * @param amount Amount of ETH to send
     * @param data Transaction data
     * @return Message number returned by the inbox
     */
    function sendUnsignedTransaction(
        uint256 maxGas,
        uint256 gasPriceBid,
        uint256 nonce,
        address destAddr,
        uint256 amount,
        bytes calldata data
    ) external returns (uint256);

    /**
     * @notice Send a contract transaction to L2
     * @param maxGas Maximum gas for the L2 transaction
     * @param gasPriceBid Gas price bid for the L2 transaction
     * @param destAddr Destination address on L2
     * @param amount Amount of ETH to send
     * @param data Transaction data
     * @return Message number returned by the inbox
     */
    function sendContractTransaction(
        uint256 maxGas,
        uint256 gasPriceBid,
        address destAddr,
        uint256 amount,
        bytes calldata data
    ) external returns (uint256);

    /**
     * @notice Send an L1-funded unsigned transaction to L2
     * @param maxGas Maximum gas for the L2 transaction
     * @param gasPriceBid Gas price bid for the L2 transaction
     * @param nonce Nonce for the transaction
     * @param destAddr Destination address on L2
     * @param data Transaction data
     * @return Message number returned by the inbox
     */
    function sendL1FundedUnsignedTransaction(
        uint256 maxGas,
        uint256 gasPriceBid,
        uint256 nonce,
        address destAddr,
        bytes calldata data
    ) external payable returns (uint256);

    /**
     * @notice Send an L1-funded contract transaction to L2
     * @param maxGas Maximum gas for the L2 transaction
     * @param gasPriceBid Gas price bid for the L2 transaction
     * @param destAddr Destination address on L2
     * @param data Transaction data
     * @return Message number returned by the inbox
     */
    function sendL1FundedContractTransaction(
        uint256 maxGas,
        uint256 gasPriceBid,
        address destAddr,
        bytes calldata data
    ) external payable returns (uint256);

    /**
     * @notice Create a retryable ticket for an L2 transaction
     * @param destAddr Destination address on L2
     * @param arbTxCallValue Call value for the L2 transaction
     * @param maxSubmissionCost Maximum cost for submitting the ticket
     * @param submissionRefundAddress Address to refund submission cost to
     * @param valueRefundAddress Address to refund excess value to
     * @param maxGas Maximum gas for the L2 transaction
     * @param gasPriceBid Gas price bid for the L2 transaction
     * @param data Transaction data
     * @return Message number returned by the inbox
     */
    function createRetryableTicket(
        address destAddr,
        uint256 arbTxCallValue,
        uint256 maxSubmissionCost,
        address submissionRefundAddress,
        address valueRefundAddress,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes calldata data
    ) external payable returns (uint256);

    /**
     * @notice Deposit ETH to L2
     * @param maxSubmissionCost Maximum cost for submitting the deposit
     * @return Message number returned by the inbox
     */
    function depositEth(uint256 maxSubmissionCost) external payable returns (uint256);

    /**
     * @notice Get the bridge contract
     * @return The bridge contract address
     */
    function bridge() external view returns (IBridge);

    /**
     * @notice Pause the creation of retryable tickets
     */
    function pauseCreateRetryables() external;

    /**
     * @notice Unpause the creation of retryable tickets
     */
    function unpauseCreateRetryables() external;

    /**
     * @notice Start rewriting addresses
     */
    function startRewriteAddress() external;

    /**
     * @notice Stop rewriting addresses
     */
    function stopRewriteAddress() external;
}
