// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

interface IGraphPayments {
    // Payment types
    enum PaymentTypes {
        QueryFee,
        IndexingFee,
        IndexingRewards
    }

    event GraphPaymentsCollected(
        address indexed sender,
        address indexed receiver,
        address indexed dataService,
        uint256 tokensReceiver,
        uint256 tokensDelegationPool,
        uint256 tokensDataService,
        uint256 tokensProtocol
    );
    // -- Errors --

    error GraphPaymentsInsufficientTokens(uint256 available, uint256 required);

    function initialize() external;

    // collect funds from a sender, pay cuts and forward the rest to the receiver
    function collect(
        PaymentTypes paymentType,
        address receiver,
        uint256 tokens,
        address dataService,
        uint256 tokensDataService
    ) external;
}
