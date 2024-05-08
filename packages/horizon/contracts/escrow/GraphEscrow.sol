// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphEscrow } from "../interfaces/IGraphEscrow.sol";
import { IGraphPayments } from "../interfaces/IGraphPayments.sol";
import { GraphDirectory } from "../GraphDirectory.sol";
import { GraphEscrowStorageV1Storage } from "./GraphEscrowStorage.sol";
import { TokenUtils } from "../utils/TokenUtils.sol";

contract GraphEscrow is IGraphEscrow, GraphEscrowStorageV1Storage, GraphDirectory {
    // -- Errors --

    error GraphEscrowNotGraphPayments();
    error GraphEscrowInputsLengthMismatch();
    error GraphEscrowInsufficientThawAmount();
    error GraphEscrowInsufficientAmount(uint256 available, uint256 required);
    error GraphEscrowNotThawing();
    error GraphEscrowStillThawing(uint256 currentTimestamp, uint256 thawEndTimestamp);
    error GraphEscrowThawingPeriodTooLong(uint256 thawingPeriod, uint256 maxThawingPeriod);
    error GraphEscrowCollectorNotAuthorized(address sender, address dataService);
    error GraphEscrowCollectorInsufficientAmount(uint256 available, uint256 required);

    // -- Events --

    event AuthorizedCollector(address indexed sender, address indexed dataService);
    event ThawCollector(address indexed sender, address indexed dataService);
    event CancelThawCollector(address indexed sender, address indexed dataService);
    event RevokeCollector(address indexed sender, address indexed dataService);
    event Deposit(address indexed sender, address indexed receiver, uint256 amount);
    event CancelThaw(address indexed sender, address indexed receiver);
    event Thaw(
        address indexed sender,
        address indexed receiver,
        uint256 amount,
        uint256 totalAmountThawing,
        uint256 thawEndTimestamp
    );
    event Withdraw(address indexed sender, address indexed receiver, uint256 amount);
    event Collect(address indexed sender, address indexed receiver, uint256 amount);

    // -- Constructor --

    constructor(
        address _controller,
        uint256 _revokeCollectorThawingPeriod,
        uint256 _withdrawEscrowThawingPeriod
    ) GraphDirectory(_controller) {
        if (_revokeCollectorThawingPeriod > MAX_THAWING_PERIOD) {
            revert GraphEscrowThawingPeriodTooLong(_revokeCollectorThawingPeriod, MAX_THAWING_PERIOD);
        }

        if (_withdrawEscrowThawingPeriod > MAX_THAWING_PERIOD) {
            revert GraphEscrowThawingPeriodTooLong(_withdrawEscrowThawingPeriod, MAX_THAWING_PERIOD);
        }

        revokeCollectorThawingPeriod = _revokeCollectorThawingPeriod;
        withdrawEscrowThawingPeriod = _withdrawEscrowThawingPeriod;
    }

    // approve a data service to collect funds
    function approveCollector(address dataService, uint256 amount) external {
        authorizedCollectors[msg.sender][dataService].authorized = true;
        authorizedCollectors[msg.sender][dataService].amount = amount;
        emit AuthorizedCollector(msg.sender, dataService);
    }

    // thaw a data service's collector authorization
    function thawCollector(address dataService) external {
        authorizedCollectors[msg.sender][dataService].thawEndTimestamp = block.timestamp + revokeCollectorThawingPeriod;
        emit ThawCollector(msg.sender, dataService);
    }

    // cancel thawing a data service's collector authorization
    function cancelThawCollector(address dataService) external {
        if (authorizedCollectors[msg.sender][dataService].thawEndTimestamp == 0) {
            revert GraphEscrowNotThawing();
        }

        authorizedCollectors[msg.sender][dataService].thawEndTimestamp = 0;
        emit CancelThawCollector(msg.sender, dataService);
    }

    // revoke authorized collector
    function revokeCollector(address dataService) external {
        Collector storage collector = authorizedCollectors[msg.sender][dataService];

        if (collector.thawEndTimestamp == 0) {
            revert GraphEscrowNotThawing();
        }

        if (collector.thawEndTimestamp > block.timestamp) {
            revert GraphEscrowStillThawing(block.timestamp, collector.thawEndTimestamp);
        }

        delete authorizedCollectors[msg.sender][dataService];
        emit RevokeCollector(msg.sender, dataService);
    }

    // Deposit funds into the escrow for a receiver
    function deposit(address receiver, uint256 amount) external {
        escrowAccounts[msg.sender][receiver].balance += amount;
        TokenUtils.pullTokens(graphToken, msg.sender, amount);
        emit Deposit(msg.sender, receiver, amount);
    }

    // Deposit funds into the escrow for multiple receivers
    function depositMany(address[] calldata receivers, uint256[] calldata amounts) external {
        if (receivers.length != amounts.length) {
            revert GraphEscrowInputsLengthMismatch();
        }

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < receivers.length; i++) {
            address receiver = receivers[i];
            uint256 amount = amounts[i];

            totalAmount += amount;
            escrowAccounts[msg.sender][receiver].balance += amount;
            emit Deposit(msg.sender, receiver, amount);
        }

        TokenUtils.pullTokens(graphToken, msg.sender, totalAmount);
    }

    // Requests to thaw a specific amount of escrow from a receiver's escrow account
    function thaw(address receiver, uint256 amount) external {
        EscrowAccount storage account = escrowAccounts[msg.sender][receiver];
        if (amount == 0) {
            // if amount thawing is zero and requested amount is zero this is an invalid request.
            // otherwise if amount thawing is greater than zero and requested amount is zero this
            // is a cancel thaw request.
            if (account.amountThawing == 0) {
                revert GraphEscrowInsufficientThawAmount();
            }
            account.amountThawing = 0;
            account.thawEndTimestamp = 0;
            emit CancelThaw(msg.sender, receiver);
            return;
        }

        // Check if the escrow balance is sufficient
        if (account.balance < amount) {
            revert GraphEscrowInsufficientAmount({ available: account.balance, required: amount });
        }

        // Set amount to thaw
        account.amountThawing = amount;
        // Set when the thaw is complete (thawing period number of seconds after current timestamp)
        account.thawEndTimestamp = block.timestamp + withdrawEscrowThawingPeriod;

        emit Thaw(msg.sender, receiver, amount, account.amountThawing, account.thawEndTimestamp);
    }

    // Withdraws all thawed escrow from a receiver's escrow account
    function withdraw(address receiver) external {
        EscrowAccount storage account = escrowAccounts[msg.sender][receiver];
        if (account.thawEndTimestamp == 0) {
            revert GraphEscrowNotThawing();
        }

        if (account.thawEndTimestamp > block.timestamp) {
            revert GraphEscrowStillThawing({
                currentTimestamp: block.timestamp,
                thawEndTimestamp: account.thawEndTimestamp
            });
        }

        // Amount is the minimum between the amount being thawed and the actual balance
        uint256 amount = account.amountThawing > account.balance ? account.balance : account.amountThawing;

        account.balance -= amount; // Reduce the balance by the withdrawn amount (no underflow risk)
        account.amountThawing = 0;
        account.thawEndTimestamp = 0;
        TokenUtils.pushTokens(graphToken, msg.sender, amount);
        emit Withdraw(msg.sender, receiver, amount);
    }

    // Collect from escrow (up to amount available in escrow) for a receiver using sender's deposit
    function collect(
        address sender,
        address receiver, // serviceProvider
        address dataService,
        uint256 amount,
        IGraphPayments.PaymentType paymentType,
        uint256 tokensDataService
    ) external {
        // Check if collector is authorized and has enough funds
        Collector storage collector = authorizedCollectors[sender][msg.sender];

        if (!collector.authorized) {
            revert GraphEscrowCollectorNotAuthorized(sender, msg.sender);
        }

        if (collector.amount < amount) {
            revert GraphEscrowCollectorInsufficientAmount(collector.amount, amount);
        }

        // Reduce amount from approved collector
        collector.amount -= amount;

        // Collect tokens from GraphEscrow up to amount available
        EscrowAccount storage account = escrowAccounts[sender][receiver];
        uint256 available = account.balance - account.amountThawing;
        uint256 collectAmount = amount > available ? available : amount;
        account.balance -= collectAmount;
        emit Collect(sender, receiver, collectAmount);

        // Approve tokens so GraphPayments can pull them
        graphToken.approve(address(graphPayments), collectAmount);
        graphPayments.collect(receiver, dataService, collectAmount, paymentType, tokensDataService);
    }
}
