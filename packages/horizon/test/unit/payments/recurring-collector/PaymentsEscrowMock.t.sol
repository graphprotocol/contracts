// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";

contract PaymentsEscrowMock is IPaymentsEscrow {
    function initialize() external {}

    function collect(IGraphPayments.PaymentTypes, address, address, uint256, address, uint256, address) external {}

    function deposit(address, address, uint256) external {}

    function depositTo(address, address, address, uint256) external {}

    function thaw(address, address, uint256) external returns (uint256) {
        return 0;
    }

    function thaw(address, address, uint256, bool /* evenIfTimerReset */) external returns (uint256) {
        return 0;
    }

    function cancelThaw(address, address) external returns (uint256) {
        return 0;
    }

    function withdraw(address, address) external returns (uint256) {
        return 0;
    }

    function getEscrowAccount(address, address, address) external pure returns (EscrowAccount memory) {
        return EscrowAccount(0, 0, 0);
    }

    function MAX_WAIT_PERIOD() external pure returns (uint256) {
        return 0;
    }

    function WITHDRAW_ESCROW_THAWING_PERIOD() external pure returns (uint256) {
        return 0;
    }
}
