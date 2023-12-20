// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "../gateway/ICallhookReceiver.sol";

/**
 * @title GovernedMock contract
 */
contract CallhookReceiverMock is ICallhookReceiver {
    event TransferReceived(address from, uint256 amount, uint256 foo, uint256 bar);

    /**
     * @dev Receive tokens with a callhook from the bridge
     * Expects two uint256 values encoded in _data.
     * Reverts if the first of these values is zero.
     * @param _from Token sender in L1
     * @param _amount Amount of tokens that were transferred
     * @param _data ABI-encoded callhook data
     */
    function onTokenTransfer(
        address _from,
        uint256 _amount,
        bytes calldata _data
    ) external override {
        uint256 foo;
        uint256 bar;
        (foo, bar) = abi.decode(_data, (uint256, uint256));
        require(foo != 0, "FOO_IS_ZERO");
        emit TransferReceived(_from, _amount, foo, bar);
    }
}
