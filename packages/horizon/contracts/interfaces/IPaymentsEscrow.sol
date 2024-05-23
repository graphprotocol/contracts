// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphPayments } from "./IGraphPayments.sol";

interface IPaymentsEscrow {
    struct EscrowAccount {
        uint256 balance; // Total escrow balance for a sender-receiver pair
        uint256 tokensThawing; // Amount of escrow currently being thawed
        uint256 thawEndTimestamp; // Timestamp at which thawing period ends (zero if not thawing)
    }

    // Collector
    struct Collector {
        bool authorized;
        uint256 allowance;
        uint256 thawEndTimestamp;
    }

    // Deposit funds into the escrow for a receiver
    function deposit(address receiver, uint256 tokens) external;

    // Requests to thaw a specific amount of escrow from a receiver's escrow account
    function thaw(address receiver, uint256 tokens) external;

    // Withdraws all thawed escrow from a receiver's escrow account
    function withdraw(address receiver) external;

    // Collect from escrow for a receiver using sender's deposit
    function collect(
        IGraphPayments.PaymentTypes paymentType,
        address payer,
        address receiver,
        uint256 tokens,
        address dataService,
        uint256 tokensDataService
    ) external;

    function getBalance(address sender, address receiver) external view returns (uint256);
}