// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable use-natspec

import { IOutbox } from "../../arbitrum/IOutbox.sol";
import { IBridge } from "../../arbitrum/IBridge.sol";

/**
 * @title Arbitrum Outbox mock contract
 * @dev This contract implements (a subset of) Arbitrum's IOutbox interface for testing purposes
 */
contract OutboxMock is IOutbox {
    /**
     * @dev Context of an L2-to-L1 function call
     * @param l2Block L2 block number
     * @param l1Block L1 block number
     * @param timestamp Timestamp of the call
     * @param batchNum Batch number
     * @param outputId Output ID
     * @param sender Address of the sender
     */
    struct L2ToL1Context {
        uint128 l2Block;
        uint128 l1Block;
        uint128 timestamp;
        uint128 batchNum;
        bytes32 outputId;
        address sender;
    }
    /// @dev Context of the current L2-to-L1 function call (set and cleared in each transaction)
    L2ToL1Context internal context;

    // Address of the (mock) Arbitrum Bridge
    IBridge public bridge;

    /**
     * @dev Set the address of the (mock) bridge
     * @param _bridge Address of the bridge
     */
    function setBridge(address _bridge) external {
        bridge = IBridge(_bridge);
    }

    /// @inheritdoc IOutbox
    function l2ToL1Sender() external view override returns (address) {
        return context.sender;
    }

    /// @inheritdoc IOutbox
    function l2ToL1Block() external view override returns (uint256) {
        return context.l2Block;
    }

    /// @inheritdoc IOutbox
    function l2ToL1EthBlock() external view override returns (uint256) {
        return context.l1Block;
    }

    /// @inheritdoc IOutbox
    function l2ToL1Timestamp() external view override returns (uint256) {
        return context.timestamp;
    }

    /// @inheritdoc IOutbox
    function l2ToL1BatchNum() external view override returns (uint256) {
        return context.batchNum;
    }

    /// @inheritdoc IOutbox
    function l2ToL1OutputId() external view override returns (bytes32) {
        return context.outputId;
    }

    /// @inheritdoc IOutbox
    function processOutgoingMessages(bytes calldata, uint256[] calldata) external pure override {
        revert("Unimplemented");
    }

    /// @inheritdoc IOutbox
    function outboxEntryExists(uint256) external pure override returns (bool) {
        return true;
    }

    /**
     * @notice (Mock) Executes a messages in an Outbox entry.
     * @dev This mocks what has to be called when finalizing an L2 to L1 transfer.
     * In our mock scenario, we don't validate and execute unconditionally.
     * @param _batchNum Index of OutboxEntry in outboxEntries array
     * @param _l2Sender sender of original message (i.e., caller of ArbSys.sendTxToL1)
     * @param _destAddr destination address for L1 contract call
     * @param _l2Block l2 block number at which sendTxToL1 call was made
     * @param _l1Block l1 block number at which sendTxToL1 call was made
     * @param _l2Timestamp l2 Timestamp at which sendTxToL1 call was made
     * @param _amount value in L1 message in wei
     * @param _calldataForL1 abi-encoded L1 message data
     */
    function executeTransaction(
        uint256 _batchNum,
        bytes32[] calldata, // proof
        uint256, // index
        address _l2Sender,
        address _destAddr,
        uint256 _l2Block,
        uint256 _l1Block,
        uint256 _l2Timestamp,
        uint256 _amount,
        bytes calldata _calldataForL1
    ) external virtual {
        bytes32 outputId;

        context = L2ToL1Context({
            sender: _l2Sender,
            l2Block: uint128(_l2Block),
            l1Block: uint128(_l1Block),
            timestamp: uint128(_l2Timestamp),
            batchNum: uint128(_batchNum),
            outputId: outputId
        });

        // set and reset vars around execution so they remain valid during call
        executeBridgeCall(_destAddr, _amount, _calldataForL1);
    }

    /**
     * @dev Execute an L2-to-L1 function call by calling the bridge
     * @param _destAddr Address of the contract to call
     * @param _amount Callvalue for the function call
     * @param _data Calldata for the function call
     */
    function executeBridgeCall(address _destAddr, uint256 _amount, bytes memory _data) internal {
        (bool success, bytes memory returndata) = bridge.executeCall(_destAddr, _amount, _data);
        if (!success) {
            if (returndata.length > 0) {
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert("BRIDGE_CALL_FAILED");
            }
        }
    }
}
