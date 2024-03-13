// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "../../arbitrum/IOutbox.sol";
import "../../arbitrum/IBridge.sol";

/**
 * @title Arbitrum Outbox mock contract
 * @dev This contract implements (a subset of) Arbitrum's IOutbox interface for testing purposes
 */
contract OutboxMock is IOutbox {
    // Context of an L2-to-L1 function call
    struct L2ToL1Context {
        uint128 l2Block;
        uint128 l1Block;
        uint128 timestamp;
        uint128 batchNum;
        bytes32 outputId;
        address sender;
    }
    // Context of the current L2-to-L1 function call (set and cleared in each transaction)
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

    /**
     * @dev Getter for the L2 sender of the current incoming message
     */
    function l2ToL1Sender() external view override returns (address) {
        return context.sender;
    }

    /**
     * @dev Getter for the L2 block of the current incoming message
     */
    function l2ToL1Block() external view override returns (uint256) {
        return context.l2Block;
    }

    /**
     * @dev Getter for the L1 block of the current incoming message
     */
    function l2ToL1EthBlock() external view override returns (uint256) {
        return context.l1Block;
    }

    /**
     * @dev Getter for the L1 timestamp of the current incoming message
     */
    function l2ToL1Timestamp() external view override returns (uint256) {
        return context.timestamp;
    }

    /**
     * @dev Getter for the L2 batch number of the current incoming message
     */
    function l2ToL1BatchNum() external view override returns (uint256) {
        return context.batchNum;
    }

    /**
     * @dev Getter for the output ID of the current incoming message
     */
    function l2ToL1OutputId() external view override returns (bytes32) {
        return context.outputId;
    }

    /**
     * @dev Unimplemented in this mock
     */
    function processOutgoingMessages(bytes calldata, uint256[] calldata) external pure override {
        revert("Unimplemented");
    }

    /**
     * @dev Check whether an outbox entry for a message exists.
     * This mock returns always true.
     */
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
