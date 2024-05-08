// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphPayments } from "../interfaces/IGraphPayments.sol";

contract GraphPaymentsStorageV1Storage {
    // The graph protocol payment cut
    uint256 public immutable protocolPaymentCut;
}
