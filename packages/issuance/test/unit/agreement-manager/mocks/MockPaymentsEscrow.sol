// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";

/// @notice Stateful mock of PaymentsEscrow for ServiceAgreementManager testing.
/// Tracks deposits per (payer, collector, receiver) and transfers tokens on deposit.
/// Supports thaw/withdraw lifecycle for updateEscrow() testing.
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
        token.transferFrom(msg.sender, address(this), tokens);
        accounts[msg.sender][collector][receiver].balance += tokens;
    }

    function thaw(address collector, address receiver, uint256 tokens) external returns (uint256) {
        return _thaw(collector, receiver, tokens, true);
    }

    function thaw(
        address collector,
        address receiver,
        uint256 tokens,
        bool evenIfTimerReset
    ) external returns (uint256) {
        return _thaw(collector, receiver, tokens, evenIfTimerReset);
    }

    function cancelThaw(address collector, address receiver) external returns (uint256) {
        return _thaw(collector, receiver, 0, true);
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

    function withdraw(address collector, address receiver) external returns (uint256 tokens) {
        Account storage account = accounts[msg.sender][collector][receiver];
        if (account.thawEndTimestamp == 0 || block.timestamp <= account.thawEndTimestamp) {
            return 0;
        }
        tokens = account.tokensThawing;
        account.balance -= tokens;
        account.tokensThawing = 0;
        account.thawEndTimestamp = 0;
        token.transfer(msg.sender, tokens);
    }

    function getEscrowAccount(
        address payer,
        address collector,
        address receiver
    ) external view returns (IPaymentsEscrow.EscrowAccount memory) {
        Account storage account = accounts[payer][collector][receiver];
        return
            IPaymentsEscrow.EscrowAccount({
                balance: account.balance,
                tokensThawing: account.tokensThawing,
                thawEndTimestamp: account.thawEndTimestamp
            });
    }

    // -- Stubs (not used by ServiceAgreementManager) --

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
