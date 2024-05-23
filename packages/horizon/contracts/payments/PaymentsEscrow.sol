// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IGraphPayments } from "../interfaces/IGraphPayments.sol";
import { IPaymentsEscrow } from "../interfaces/IPaymentsEscrow.sol";

import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";

import { GraphDirectory } from "../data-service/GraphDirectory.sol";

contract PaymentsEscrow is Multicall, GraphDirectory, IPaymentsEscrow {
    using TokenUtils for IGraphToken;

    // Authorized collectors
    mapping(address sender => mapping(address dataService => IPaymentsEscrow.Collector collector))
        public authorizedCollectors;

    // Stores how much escrow each sender has deposited for each receiver, as well as thawing information
    mapping(address sender => mapping(address receiver => IPaymentsEscrow.EscrowAccount escrowAccount))
        public escrowAccounts;

    // The maximum thawing period (in seconds) for both escrow withdrawal and signer revocation
    // This is a precautionary measure to avoid inadvertedly locking funds for too long
    uint256 public constant MAX_THAWING_PERIOD = 90 days;

    // Thawing period for authorized collectors
    uint256 public immutable REVOKE_COLLECTOR_THAWING_PERIOD;

    // The duration (in seconds) in which escrow funds are thawing before they can be withdrawn
    uint256 public immutable WITHDRAW_ESCROW_THAWING_PERIOD;

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

    error GraphEscrowNotGraphPayments();
    error GraphEscrowInputsLengthMismatch();
    error GraphEscrowInsufficientTokensThawing();
    error GraphEscrowInsufficientBalance(uint256 available, uint256 required);
    error GraphEscrowNotThawing();
    error GraphEscrowStillThawing(uint256 currentTimestamp, uint256 thawEndTimestamp);
    error GraphEscrowThawingPeriodTooLong(uint256 thawingPeriod, uint256 maxThawingPeriod);
    error GraphEscrowCollectorNotAuthorized(address sender, address dataService);
    error GraphEscrowInsufficientAllowance(uint256 available, uint256 required);
    error PaymentsEscrowInconsistentCollection(uint256 balanceBefore, uint256 balanceAfter, uint256 tokens);

    // -- Constructor --

    constructor(
        address controller,
        uint256 revokeCollectorThawingPeriod,
        uint256 withdrawEscrowThawingPeriod
    ) GraphDirectory(controller) {
        if (revokeCollectorThawingPeriod > MAX_THAWING_PERIOD) {
            revert GraphEscrowThawingPeriodTooLong(revokeCollectorThawingPeriod, MAX_THAWING_PERIOD);
        }

        if (withdrawEscrowThawingPeriod > MAX_THAWING_PERIOD) {
            revert GraphEscrowThawingPeriodTooLong(withdrawEscrowThawingPeriod, MAX_THAWING_PERIOD);
        }

        REVOKE_COLLECTOR_THAWING_PERIOD = revokeCollectorThawingPeriod;
        WITHDRAW_ESCROW_THAWING_PERIOD = withdrawEscrowThawingPeriod;
    }

    // approve a data service to collect funds
    function approveCollector(address dataService, uint256 tokens) external {
        Collector storage collector = authorizedCollectors[msg.sender][dataService];
        if (collector.allowance > tokens) {
            revert GraphEscrowInsufficientAllowance(collector.allowance, tokens);
        }

        collector.authorized = true;
        collector.allowance = tokens;
        emit AuthorizedCollector(msg.sender, dataService);
    }

    // thaw a data service's collector authorization
    function thawCollector(address dataService) external {
        authorizedCollectors[msg.sender][dataService].thawEndTimestamp =
            block.timestamp +
            REVOKE_COLLECTOR_THAWING_PERIOD;
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
    function deposit(address receiver, uint256 tokens) external {
        escrowAccounts[msg.sender][receiver].balance += tokens;
        _graphToken().pullTokens(msg.sender, tokens);
        emit Deposit(msg.sender, receiver, tokens);
    }

    // Requests to thaw a specific amount of escrow from a receiver's escrow account
    function thaw(address receiver, uint256 tokens) external {
        EscrowAccount storage account = escrowAccounts[msg.sender][receiver];
        if (tokens == 0) {
            // if amount thawing is zero and requested amount is zero this is an invalid request.
            // otherwise if amount thawing is greater than zero and requested amount is zero this
            // is a cancel thaw request.
            if (account.tokensThawing == 0) {
                revert GraphEscrowInsufficientTokensThawing();
            }
            account.tokensThawing = 0;
            account.thawEndTimestamp = 0;
            emit CancelThaw(msg.sender, receiver);
            return;
        }

        // Check if the escrow balance is sufficient
        if (account.balance < tokens) {
            revert GraphEscrowInsufficientBalance(account.balance, tokens);
        }

        // Set amount to thaw
        account.tokensThawing = tokens;
        // Set when the thaw is complete (thawing period number of seconds after current timestamp)
        account.thawEndTimestamp = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;

        emit Thaw(msg.sender, receiver, tokens, account.tokensThawing, account.thawEndTimestamp);
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
        uint256 tokens = account.tokensThawing > account.balance ? account.balance : account.tokensThawing;

        account.balance -= tokens; // Reduce the balance by the withdrawn amount (no underflow risk)
        account.tokensThawing = 0;
        account.thawEndTimestamp = 0;
        _graphToken().pushTokens(msg.sender, tokens);
        emit Withdraw(msg.sender, receiver, tokens);
    }

    // Collect from escrow for a receiver using sender's deposit
    function collect(
        IGraphPayments.PaymentTypes paymentType,
        address payer,
        address receiver,
        uint256 tokens,
        address dataService,
        uint256 tokensDataService
    ) external {
        // Check if collector is authorized and has enough funds
        Collector storage collector = authorizedCollectors[payer][msg.sender];

        if (!collector.authorized) {
            revert GraphEscrowCollectorNotAuthorized(payer, msg.sender);
        }

        if (collector.allowance < tokens) {
            revert GraphEscrowInsufficientAllowance(collector.allowance, tokens);
        }

        // Reduce amount from approved collector
        collector.allowance -= tokens;

        // Collect tokens from GraphEscrow up to amount available
        EscrowAccount storage account = escrowAccounts[payer][receiver];
        uint256 availableTokens = account.balance - account.tokensThawing;
        if (availableTokens < tokens) {
            revert GraphEscrowInsufficientBalance(availableTokens, tokens);
        }

        account.balance -= tokens;

        // Approve tokens so GraphPayments can pull them
        uint256 balanceBefore = _graphToken().balanceOf(address(this));

        _graphToken().approve(address(_graphPayments()), tokens);
        _graphPayments().collect(paymentType, receiver, tokens, dataService, tokensDataService);

        uint256 balanceAfter = _graphToken().balanceOf(address(this));
        if (balanceBefore - balanceAfter != tokens) {
            revert PaymentsEscrowInconsistentCollection(balanceBefore, balanceAfter, tokens);
        }

        emit EscrowCollected(payer, receiver, tokens);
    }

    // Get the balance of a sender-receiver pair
    function getBalance(address payer, address receiver) external view returns (uint256) {
        EscrowAccount storage account = escrowAccounts[payer][receiver];
        return account.balance - account.tokensThawing;
    }
}
