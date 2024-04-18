// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

interface IGraphPayments {
    // Payment types
    enum PaymentType {
        IndexingFees,
        QueryFees
    }

    // Authorized collector
    struct Collector {
        bool authorized;
        uint256 thawEndTimestamp;
    }

    // approve a data service to collect funds
    function approveCollector(address dataService) external;

    // thaw a data service's collector authorization
    function thawCollector(address dataService) external;

    // cancel thawing a data service's collector authorization
    function cancelThawCollector(address dataService) external;

    // revoke authorized collector
    function revokeCollector(address dataService) external;

    // collect funds from a sender, pay cuts and forward the rest to the receiver
    function collect(
        address sender,
        address receiver,
        uint256 amount,
        PaymentType paymentType,
        uint256 dataServiceCut
    ) external;
}
