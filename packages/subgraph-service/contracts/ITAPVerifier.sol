// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

interface ITAPVerifier {
    struct ReceiptAggregateVoucher {
        address allocationId;
        uint64 timestampNs;
        uint128 valueAggregate;
    }

    struct SignedRAV {
        ReceiptAggregateVoucher rav;
        bytes signature;
    }
}
