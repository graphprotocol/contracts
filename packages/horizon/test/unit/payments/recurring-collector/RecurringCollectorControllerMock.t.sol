// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";

import { IPaymentsEscrow } from "../../../../contracts/interfaces/IPaymentsEscrow.sol";
import { ControllerMock } from "../../../../contracts/mocks/ControllerMock.sol";

contract RecurringCollectorControllerMock is ControllerMock, Test {
    address private _invalidContractAddress;
    IPaymentsEscrow private _paymentsEscrow;

    constructor(address paymentsEscrow) ControllerMock(address(0)) {
        _invalidContractAddress = makeAddr("invalidContractAddress");
        _paymentsEscrow = IPaymentsEscrow(paymentsEscrow);
    }

    function getContractProxy(bytes32 data) external view override returns (address) {
        return data == keccak256("PaymentsEscrow") ? address(_paymentsEscrow) : _invalidContractAddress;
    }

    function getPaymentsEscrow() external view returns (address) {
        return address(_paymentsEscrow);
    }
}
