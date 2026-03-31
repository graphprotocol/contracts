// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";

/// @notice Stateful mock of PaymentsEscrow for RecurringAgreementManager testing.
/// Tracks deposits per (payer, collector, receiver) and transfers tokens on deposit.
/// Supports thaw/withdraw lifecycle for escrow rebalancing testing.
contract MockPaymentsEscrow is IPaymentsEscrow {
    IERC20 public token;

    struct Account {
        uint256 balance;
        uint256 tokensThawing;
        uint256 thawEndTimestamp;
    }

    // accounts[payer][collector][receiver]
    mapping(address => mapping(address => mapping(address => Account))) public accounts;

    /// @notice Thawing period for testing (set to 1 day by default)
    uint256 public constant THAWING_PERIOD = 1 days;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function deposit(address collector, address receiver, uint256 tokens) external {
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transferFrom(msg.sender, address(this), tokens);
        accounts[msg.sender][collector][receiver].balance += tokens;
    }

    function thaw(address collector, address receiver, uint256 tokens) external {
        _thaw(collector, receiver, tokens, true);
    }

    function adjustThaw(
        address collector,
        address receiver,
        uint256 tokens,
        bool evenIfTimerReset
    ) external returns (uint256) {
        return _thaw(collector, receiver, tokens, evenIfTimerReset);
    }

    function cancelThaw(address collector, address receiver) external {
        _thaw(collector, receiver, 0, true);
    }

    function _thaw(
        address collector,
        address receiver,
        uint256 tokens,
        bool evenIfTimerReset
    ) private returns (uint256 tokensThawing) {
        Account storage account = accounts[msg.sender][collector][receiver];
        tokensThawing = tokens < account.balance ? tokens : account.balance;
        if (tokensThawing == account.tokensThawing) {
            return tokensThawing;
        }
        uint256 newThawEndTimestamp = block.timestamp + THAWING_PERIOD;
        if (tokensThawing < account.tokensThawing) {
            account.tokensThawing = tokensThawing;
            if (tokensThawing == 0) account.thawEndTimestamp = 0;
        } else {
            if (!evenIfTimerReset && account.thawEndTimestamp != 0 && account.thawEndTimestamp != newThawEndTimestamp)
                return account.tokensThawing;
            account.tokensThawing = tokensThawing;
            account.thawEndTimestamp = newThawEndTimestamp;
        }
    }

    function withdraw(address collector, address receiver) external {
        Account storage account = accounts[msg.sender][collector][receiver];
        if (account.thawEndTimestamp == 0 || block.timestamp <= account.thawEndTimestamp) {
            return;
        }
        uint256 tokens = account.tokensThawing;
        account.balance -= tokens;
        account.tokensThawing = 0;
        account.thawEndTimestamp = 0;
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transfer(msg.sender, tokens);
    }

    function escrowAccounts(
        address payer,
        address collector,
        address receiver
    ) external view returns (uint256, uint256, uint256) {
        Account storage account = accounts[payer][collector][receiver];
        return (account.balance, account.tokensThawing, account.thawEndTimestamp);
    }

    function getBalance(address payer, address collector, address receiver) external view returns (uint256) {
        Account storage account = accounts[payer][collector][receiver];
        return account.tokensThawing < account.balance ? account.balance - account.tokensThawing : 0;
    }

    /// @notice Test helper: set arbitrary account state for data-driven tests
    function setAccount(
        address payer,
        address collector,
        address receiver,
        uint256 balance_,
        uint256 tokensThawing_,
        uint256 thawEndTimestamp_
    ) external {
        Account storage account = accounts[payer][collector][receiver];
        account.balance = balance_;
        account.tokensThawing = tokensThawing_;
        account.thawEndTimestamp = thawEndTimestamp_;
    }

    // -- Stubs (not used by RecurringAgreementManager) --

    function initialize() external {}
    function depositTo(address, address, address, uint256) external {}
    function collect(IGraphPayments.PaymentTypes, address, address, uint256, address, uint256, address) external {}
    function MAX_WAIT_PERIOD() external pure returns (uint256) {
        return 0;
    }
    function WITHDRAW_ESCROW_THAWING_PERIOD() external pure returns (uint256) {
        return THAWING_PERIOD;
    }
}
