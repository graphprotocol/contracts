// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

interface IGraphPayments {
    function approveCollector(address dataService) external;
    function collect(
        address sender,
        address receiver,
        uint256 amount,
        uint256 paymentType,
        uint256 dataServiceCut
    ) external;
}
