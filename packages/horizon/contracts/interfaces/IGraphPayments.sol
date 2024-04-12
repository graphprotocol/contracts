// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

interface IGraphPayments {
    // approve a data service to collect funds
    function approveCollector(address dataService) external;

    // collect funds from a sender, pay cuts and forward the rest to the receiver
    function collect(
        address sender,
        address receiver,
        uint256 amount,
        uint256 paymentType,
        uint256 dataServiceCut
    ) external;
}
