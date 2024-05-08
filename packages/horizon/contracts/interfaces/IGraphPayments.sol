// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

interface IGraphPayments {
    // Payment types
    enum PaymentType {
        IndexingFees,
        QueryFees
    }

    // collect funds from a sender, pay cuts and forward the rest to the receiver
    function collect(
        address receiver,
        address dataService,
        uint256 amount,
        PaymentType paymentType,
        uint256 tokensDataService
    ) external;
}
