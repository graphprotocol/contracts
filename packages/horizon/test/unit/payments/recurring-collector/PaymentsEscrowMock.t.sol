// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IGraphPayments } from "../../../../contracts/interfaces/IGraphPayments.sol";
import { IPaymentsEscrow } from "../../../../contracts/interfaces/IPaymentsEscrow.sol";

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
}
