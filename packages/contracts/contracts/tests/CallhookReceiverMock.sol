// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events, use-natspec

import { ICallhookReceiver } from "../gateway/ICallhookReceiver.sol";

/**
 * @title CallhookReceiverMock contract
 * @dev Mock contract for testing callhook receiver functionality
 */
contract CallhookReceiverMock is ICallhookReceiver {
    /**
     * @dev Emitted when a transfer is received
     * @param from Address that sent the transfer
     * @param amount Amount of tokens transferred
     * @param foo First test parameter
     * @param bar Second test parameter
     */
    event TransferReceived(address from, uint256 amount, uint256 foo, uint256 bar);

    /**
     * @inheritdoc ICallhookReceiver
     * @dev Expects two uint256 values encoded in _data.
     * Reverts if the first of these values is zero.
     */
    function onTokenTransfer(address _from, uint256 _amount, bytes calldata _data) external override {
        uint256 foo;
        uint256 bar;
        (foo, bar) = abi.decode(_data, (uint256, uint256));
        require(foo != 0, "FOO_IS_ZERO");
        emit TransferReceived(_from, _amount, foo, bar);
    }
}
