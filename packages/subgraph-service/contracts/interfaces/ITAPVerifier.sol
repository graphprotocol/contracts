// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

interface ITAPVerifier {
    struct ReceiptAggregateVoucher {
        address serviceProvider;
        address dataService;
        uint64 timestampNs;
        uint128 valueAggregate;
    }

    struct SignedRAV {
        ReceiptAggregateVoucher rav;
        bytes signature; // 65 bytes: r (32 Bytes) || s (32 Bytes) || v (1 Byte)
    }

    function verify(SignedRAV calldata rav) external returns (address);
}
