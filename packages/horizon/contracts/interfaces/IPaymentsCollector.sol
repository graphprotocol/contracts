// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.26;

import { IGraphPayments } from "./IGraphPayments.sol";

interface IPaymentsCollector {
    function collect(IGraphPayments.PaymentTypes paymentType, bytes memory data) external returns (uint256);
}
