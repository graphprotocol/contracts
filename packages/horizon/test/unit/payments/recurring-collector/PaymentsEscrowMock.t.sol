// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";

contract PaymentsEscrowMock is IPaymentsEscrow {
    function initialize() external {}

    function collect(IGraphPayments.PaymentTypes, address, address, uint256, address, uint256, address) external {}

    function deposit(address, address, uint256) external {}

    function depositTo(address, address, address, uint256) external {}

    function thaw(address, address, uint256) external {}

    function cancelThaw(address, address) external {}

    function withdraw(address, address) external {}

    function getBalance(address, address, address) external pure returns (uint256) {
        return 0;
    }

    function MAX_WAIT_PERIOD() external pure returns (uint256) {
        return 0;
    }

    function WITHDRAW_ESCROW_THAWING_PERIOD() external pure returns (uint256) {
        return 0;
    }
}
