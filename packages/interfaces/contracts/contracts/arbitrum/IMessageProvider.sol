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

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title Message Provider Interface
 * @author Edge & Node
 * @notice Interface for Arbitrum message providers
 */
interface IMessageProvider {
    /**
     * @notice Emitted when a message is delivered to the inbox
     * @param messageNum Message number
     * @param data Message data
     */
    event InboxMessageDelivered(uint256 indexed messageNum, bytes data);

    /**
     * @notice Emitted when a message is delivered from origin
     * @param messageNum Message number
     */
    event InboxMessageDeliveredFromOrigin(uint256 indexed messageNum);
}
