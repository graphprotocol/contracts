// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IPaymentsCollector } from "./IPaymentsCollector.sol";

interface ITAPCollector is IPaymentsCollector {
    struct ReceiptAggregateVoucher {
        address dataService;
        address serviceProvider;
        uint64 timestampNs;
        uint128 valueAggregate;
        bytes metadata;
    }

    struct SignedRAV {
        ReceiptAggregateVoucher rav;
        bytes signature; // 65 bytes: r (32 Bytes) || s (32 Bytes) || v (1 Byte)
    }
}
