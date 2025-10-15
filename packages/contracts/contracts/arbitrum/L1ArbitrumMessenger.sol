// SPDX-License-Identifier: Apache-2.0

/*
 * Copyright 2020, Offchain Labs, Inc.
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
 * https://github.com/OffchainLabs/arbitrum/tree/e3a6307ad8a2dc2cad35728a2a9908cfd8dd8ef9/packages/arb-bridge-peripherals
 *
 * MODIFIED from Offchain Labs' implementation:
 * - Changed solidity version to 0.7.6 (pablo@edgeandnode.com)
 *
 */

pragma solidity ^0.7.6;

import { IInbox } from "./IInbox.sol";
import { IOutbox } from "./IOutbox.sol";
import { IBridge } from "./IBridge.sol";

/**
 * @title L1 Arbitrum Messenger
 * @author Edge & Node
 * @notice L1 utility contract to assist with L1 <=> L2 interactions
 * @dev this is an abstract contract instead of library so the functions can be easily overridden when testing
 */
abstract contract L1ArbitrumMessenger {
    /**
     * @notice Emitted when a transaction is sent to L2
     * @param _from Address sending the transaction
     * @param _to Address receiving the transaction on L2
     * @param _seqNum Sequence number of the retryable ticket
     * @param _data Transaction data
     */
    event TxToL2(address indexed _from, address indexed _to, uint256 indexed _seqNum, bytes _data);

    /**
     * @dev Parameters for L2 gas configuration
     * @param _maxSubmissionCost Maximum cost for submitting the transaction
     * @param _maxGas Maximum gas for the L2 transaction
     * @param _gasPriceBid Gas price bid for the L2 transaction
     */
    struct L2GasParams {
        uint256 _maxSubmissionCost;
        uint256 _maxGas;
        uint256 _gasPriceBid;
    }

    /**
     * @notice Send a transaction to L2 using gas parameters struct
     * @param _inbox Address of the inbox contract
     * @param _to Destination address on L2
     * @param _user Address that will be credited as the sender
     * @param _l1CallValue ETH value to send with the L1 transaction
     * @param _l2CallValue ETH value to send with the L2 transaction
     * @param _l2GasParams Gas parameters for the L2 transaction
     * @param _data Calldata for the L2 transaction
     * @return Sequence number of the retryable ticket
     */
    function sendTxToL2(
        address _inbox,
        address _to,
        address _user,
        uint256 _l1CallValue,
        uint256 _l2CallValue,
        L2GasParams memory _l2GasParams,
        bytes memory _data
    ) internal virtual returns (uint256) {
        // alternative function entry point when struggling with the stack size
        return
            sendTxToL2(
                _inbox,
                _to,
                _user,
                _l1CallValue,
                _l2CallValue,
                _l2GasParams._maxSubmissionCost,
                _l2GasParams._maxGas,
                _l2GasParams._gasPriceBid,
                _data
            );
    }

    /**
     * @notice Send a transaction to L2 with individual gas parameters
     * @param _inbox Address of the inbox contract
     * @param _to Destination address on L2
     * @param _user Address that will be credited as the sender
     * @param _l1CallValue ETH value to send with the L1 transaction
     * @param _l2CallValue ETH value to send with the L2 transaction
     * @param _maxSubmissionCost Maximum cost for submitting the transaction
     * @param _maxGas Maximum gas for the L2 transaction
     * @param _gasPriceBid Gas price bid for the L2 transaction
     * @param _data Calldata for the L2 transaction
     * @return Sequence number of the retryable ticket
     */
    function sendTxToL2(
        address _inbox,
        address _to,
        address _user,
        uint256 _l1CallValue,
        uint256 _l2CallValue,
        uint256 _maxSubmissionCost,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes memory _data
    ) internal virtual returns (uint256) {
        uint256 seqNum = IInbox(_inbox).createRetryableTicket{ value: _l1CallValue }(
            _to,
            _l2CallValue,
            _maxSubmissionCost,
            _user,
            _user,
            _maxGas,
            _gasPriceBid,
            _data
        );
        emit TxToL2(_user, _to, seqNum, _data);
        return seqNum;
    }

    /**
     * @notice Get the bridge contract from an inbox
     * @param _inbox Address of the inbox contract
     * @return Bridge contract interface
     */
    function getBridge(address _inbox) internal view virtual returns (IBridge) {
        return IInbox(_inbox).bridge();
    }

    /**
     * @notice Get the L2 to L1 sender address from the outbox
     * @dev the l2ToL1Sender behaves as the tx.origin, the msg.sender should be validated to protect against reentrancies
     * @param _inbox Address of the inbox contract
     * @return Address of the L2 to L1 sender
     */
    function getL2ToL1Sender(address _inbox) internal view virtual returns (address) {
        IOutbox outbox = IOutbox(getBridge(_inbox).activeOutbox());
        address l2ToL1Sender = outbox.l2ToL1Sender();

        require(l2ToL1Sender != address(0), "NO_SENDER");
        return l2ToL1Sender;
    }
}
