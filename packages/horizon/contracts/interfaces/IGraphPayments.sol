// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

interface IGraphPayments {
    // Payment types
    enum PaymentTypes {
        QueryFee,
        IndexingFee,
        IndexingRewards
    }

    // -- Errors --

    error GraphPaymentsInsufficientTokens(uint256 available, uint256 required);

    // collect funds from a sender, pay cuts and forward the rest to the receiver
    function collect(
        PaymentTypes paymentType,
        address receiver,
        uint256 tokens,
        address dataService,
        uint256 tokensDataService
    ) external;
}
