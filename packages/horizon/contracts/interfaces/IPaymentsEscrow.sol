// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

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

    // -- Events --

    event AuthorizedCollector(address indexed payer, address indexed dataService);
    event ThawCollector(address indexed payer, address indexed dataService);
    event CancelThawCollector(address indexed payer, address indexed dataService);
    event RevokeCollector(address indexed payer, address indexed dataService);
    event Deposit(address indexed payer, address indexed receiver, uint256 tokens);
    event CancelThaw(address indexed payer, address indexed receiver);
    event Thaw(
        address indexed payer,
        address indexed receiver,
        uint256 tokens,
        uint256 totalTokensThawing,
        uint256 thawEndTimestamp
    );
    event Withdraw(address indexed payer, address indexed receiver, uint256 tokens);
    event EscrowCollected(address indexed payer, address indexed receiver, uint256 tokens);

    // -- Errors --

    error PaymentsEscrowInsufficientTokensThawing();
    error PaymentsEscrowInsufficientBalance(uint256 available, uint256 required);
    error PaymentsEscrowNotThawing();
    error PaymentsEscrowStillThawing(uint256 currentTimestamp, uint256 thawEndTimestamp);
    error PaymentsEscrowThawingPeriodTooLong(uint256 thawingPeriod, uint256 maxThawingPeriod);
    error PaymentsEscrowCollectorNotAuthorized(address sender, address dataService);
    error PaymentsEscrowInsufficientAllowance(uint256 available, uint256 required);
    error PaymentsEscrowInconsistentCollection(uint256 balanceBefore, uint256 balanceAfter, uint256 tokens);

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
