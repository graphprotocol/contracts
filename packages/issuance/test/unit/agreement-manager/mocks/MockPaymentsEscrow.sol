// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";

/// @notice Stateful mock of PaymentsEscrow for IndexingAgreementManager testing.
/// Tracks deposits per (payer, collector, receiver) and transfers tokens on deposit.
/// Supports thaw/withdraw lifecycle for maintain() testing.
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

    function getBalance(address payer, address collector, address receiver) external view returns (uint256) {
        Account storage account = accounts[payer][collector][receiver];
        return account.balance > account.tokensThawing ? account.balance - account.tokensThawing : 0;
    }

    function thaw(address collector, address receiver, uint256 tokens) external {
        Account storage account = accounts[msg.sender][collector][receiver];
        require(account.balance >= tokens, "insufficient balance");
        account.tokensThawing = tokens;
        account.thawEndTimestamp = block.timestamp + THAWING_PERIOD;
    }

    function cancelThaw(address collector, address receiver) external {
        Account storage account = accounts[msg.sender][collector][receiver];
        account.tokensThawing = 0;
        account.thawEndTimestamp = 0;
    }

    function withdraw(address collector, address receiver) external {
        Account storage account = accounts[msg.sender][collector][receiver];
        require(account.thawEndTimestamp != 0, "not thawing");
        require(account.thawEndTimestamp < block.timestamp, "still thawing");

        uint256 tokens = account.tokensThawing > account.balance ? account.balance : account.tokensThawing;
        account.balance -= tokens;
        account.tokensThawing = 0;
        account.thawEndTimestamp = 0;
        token.transfer(msg.sender, tokens);
    }

    // -- Stubs (not used by IndexingAgreementManager) --

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
