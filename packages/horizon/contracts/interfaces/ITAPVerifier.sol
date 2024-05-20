// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

interface ITAPVerifier {
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

    struct SenderAuthorization {
        address sender; // Sender the signer is authorized to sign for
        uint256 thawEndTimestamp; // Timestamp at which thawing period ends (zero if not thawing)
    }

    function verify(SignedRAV calldata rav) external returns (address sender);
}
