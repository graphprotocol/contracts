// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphPayments } from "../interfaces/IGraphPayments.sol";

interface IDataService {
    function register(address serviceProvider, bytes calldata data) external;

    function redeem(IGraphPayments.PaymentTypes feeType, bytes calldata data) external returns (uint256 feesCollected);
}
