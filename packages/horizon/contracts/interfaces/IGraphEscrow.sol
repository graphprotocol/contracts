// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphPayments } from "./IGraphPayments.sol";

interface IGraphEscrow {
    struct EscrowAccount {
        uint256 balance; // Total escrow balance for a sender-receiver pair
        uint256 amountThawing; // Amount of escrow currently being thawed
        uint256 thawEndTimestamp; // Timestamp at which thawing period ends (zero if not thawing)
    }

    // Collector
    struct Collector {
        bool authorized;
        uint256 amount;
        uint256 thawEndTimestamp;
    }

    // Deposit funds into the escrow for a receiver
    function deposit(address receiver, uint256 amount) external;

    // Deposit funds into the escrow for multiple receivers
    function depositMany(address[] calldata receivers, uint256[] calldata amounts) external;

    // Requests to thaw a specific amount of escrow from a receiver's escrow account
    function thaw(address receiver, uint256 amount) external;

    // Withdraws all thawed escrow from a receiver's escrow account
    function withdraw(address receiver) external;

    // Collect from escrow (up to amount available in escrow) for a receiver using sender's deposit
    function collect(
        address sender,
        address receiver,
        address dataService,
        uint256 amount,
        IGraphPayments.PaymentType paymentType,
        uint256 tokensDataService
    ) external;
}
