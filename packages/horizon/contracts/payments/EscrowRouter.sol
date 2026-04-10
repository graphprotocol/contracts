// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.27;

// solhint-disable gas-strict-inequalities

import { IGraphToken } from "@graphprotocol/interfaces/contracts/contracts/token/IGraphToken.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { MulticallUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";

import { GraphDirectory } from "../utilities/GraphDirectory.sol";

/**
 * @title EscrowRouter contract
 * @notice Thin routing layer implementing {IPaymentsEscrow}. Registered as "PaymentsEscrow"
 * in the Controller so that all contracts (via GraphDirectory) get this as their escrow
 * reference.
 *
 * Provides standard escrow functionality (deposit/thaw/withdraw/collect) identical to
 * {PaymentsEscrow}. Adds a governance-controlled override mapping: when an override is
 * set for a payer, `collect()` and `getBalance()` delegate to the override implementation
 * (e.g., IndexingSignal virtual escrow). All other operations (deposit, thaw, withdraw)
 * always use the router's own escrow storage.
 *
 * @author Edge & Node
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract EscrowRouter is Initializable, MulticallUpgradeable, GraphDirectory, IPaymentsEscrow {
    using TokenUtils for IGraphToken;

    /// @notice The maximum thawing period (in seconds) for escrow withdrawal
    uint256 public constant MAX_WAIT_PERIOD = 90 days;

    /// @notice Thawing period in seconds for escrow funds withdrawal
    uint256 public immutable WITHDRAW_ESCROW_THAWING_PERIOD;

    /// @notice Escrow account details for payer-collector-receiver tuples (standard flows)
    mapping(address payer => mapping(address collector => mapping(address receiver => IPaymentsEscrow.EscrowAccount)))
        public escrowAccounts;

    /// @notice Governance-controlled override: payer -> escrow implementation.
    /// When set, collect() and getBalance() for this payer delegate to the override.
    /// Zero address means use standard escrow (this contract's own storage).
    mapping(address payer => IPaymentsEscrow escrow) public escrowOverrides;

    /**
     * @notice Emitted when an escrow override is set or removed for a payer
     * @param payer The payer address for which the override is set
     * @param escrowOverride The override escrow implementation address (zero address to remove)
     */
    event EscrowOverrideSet(address indexed payer, address indexed escrowOverride);

    /// @notice Thrown when a non-governor calls a governor-only function
    error EscrowRouterNotGovernor();

    // forge-lint: disable-next-item(unwrapped-modifier-logic)
    modifier notPaused() {
        require(!_graphController().paused(), PaymentsEscrowIsPaused());
        _;
    }

    // forge-lint: disable-next-item(unwrapped-modifier-logic)
    modifier onlyGovernor() {
        _onlyGovernor();
        _;
    }

    /**
     * @notice Construct the EscrowRouter contract
     * @param controller The address of the Controller
     * @param withdrawEscrowThawingPeriod Thawing period in seconds for escrow withdrawal
     */
    constructor(address controller, uint256 withdrawEscrowThawingPeriod) GraphDirectory(controller) {
        require(
            withdrawEscrowThawingPeriod <= MAX_WAIT_PERIOD,
            PaymentsEscrowThawingPeriodTooLong(withdrawEscrowThawingPeriod, MAX_WAIT_PERIOD)
        );

        WITHDRAW_ESCROW_THAWING_PERIOD = withdrawEscrowThawingPeriod;
        _disableInitializers();
    }

    /// @inheritdoc IPaymentsEscrow
    function initialize() external initializer {
        __Multicall_init();
    }

    // -- Governance --

    /**
     * @notice Set or remove an escrow override for a payer.
     * When set, collect() and getBalance() for this payer delegate to the override.
     * Set to zero address to remove the override (revert to standard escrow).
     * @param payer The payer address to set the override for
     * @param escrowOverride The override implementation (zero address to remove)
     */
    function setEscrowOverride(address payer, IPaymentsEscrow escrowOverride) external onlyGovernor {
        escrowOverrides[payer] = escrowOverride;
        emit EscrowOverrideSet(payer, address(escrowOverride));
    }

    // -- Standard Escrow Operations --
    // These always use the router's own storage (no override delegation).

    /// @inheritdoc IPaymentsEscrow
    function deposit(address collector, address receiver, uint256 tokens) external override notPaused {
        _deposit(msg.sender, collector, receiver, tokens);
    }

    /// @inheritdoc IPaymentsEscrow
    function depositTo(address payer, address collector, address receiver, uint256 tokens) external override notPaused {
        _deposit(payer, collector, receiver, tokens);
    }

    /// @inheritdoc IPaymentsEscrow
    function thaw(address collector, address receiver, uint256 tokens) external override notPaused {
        require(tokens > 0, PaymentsEscrowInvalidZeroTokens());

        EscrowAccount storage account = escrowAccounts[msg.sender][collector][receiver];
        require(account.balance >= tokens, PaymentsEscrowInsufficientBalance(account.balance, tokens));

        account.tokensThawing = tokens;
        account.thawEndTimestamp = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;

        emit Thaw(msg.sender, collector, receiver, tokens, account.thawEndTimestamp);
    }

    /// @inheritdoc IPaymentsEscrow
    function adjustThaw(
        address collector,
        address receiver,
        uint256 tokensToThaw,
        bool evenIfTimerReset
    ) external override notPaused returns (uint256 tokensThawing) {
        EscrowAccount storage account = escrowAccounts[msg.sender][collector][receiver];
        uint256 currentThawing = account.tokensThawing;

        tokensThawing = tokensToThaw < account.balance ? tokensToThaw : account.balance;

        if (tokensThawing == currentThawing) return tokensThawing;

        uint256 thawEndTimestamp;
        uint256 previousThawEnd = account.thawEndTimestamp;
        if (tokensThawing < currentThawing) {
            account.tokensThawing = tokensThawing;
            if (tokensThawing == 0) account.thawEndTimestamp = 0;
            else thawEndTimestamp = previousThawEnd;
        } else {
            thawEndTimestamp = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;
            if (!evenIfTimerReset && previousThawEnd != 0 && previousThawEnd != thawEndTimestamp) return currentThawing;
            account.tokensThawing = tokensThawing;
            account.thawEndTimestamp = thawEndTimestamp;
        }

        emit Thaw(msg.sender, collector, receiver, tokensThawing, thawEndTimestamp);
    }

    /// @inheritdoc IPaymentsEscrow
    function cancelThaw(address collector, address receiver) external override notPaused {
        EscrowAccount storage account = escrowAccounts[msg.sender][collector][receiver];
        require(account.tokensThawing != 0, PaymentsEscrowNotThawing());

        uint256 tokensThawing = account.tokensThawing;
        uint256 thawEndTimestamp = account.thawEndTimestamp;
        account.tokensThawing = 0;
        account.thawEndTimestamp = 0;

        emit CancelThaw(msg.sender, collector, receiver, tokensThawing, thawEndTimestamp);
    }

    /// @inheritdoc IPaymentsEscrow
    function withdraw(address collector, address receiver) external override notPaused {
        EscrowAccount storage account = escrowAccounts[msg.sender][collector][receiver];
        require(account.thawEndTimestamp != 0, PaymentsEscrowNotThawing());
        require(
            account.thawEndTimestamp < block.timestamp,
            PaymentsEscrowStillThawing(block.timestamp, account.thawEndTimestamp)
        );

        uint256 tokens = account.tokensThawing > account.balance ? account.balance : account.tokensThawing;

        account.balance -= tokens;
        account.tokensThawing = 0;
        account.thawEndTimestamp = 0;
        _graphToken().pushTokens(msg.sender, tokens);
        emit Withdraw(msg.sender, collector, receiver, tokens);
    }

    // -- Routed Operations --

    /// @inheritdoc IPaymentsEscrow
    function collect(
        IGraphPayments.PaymentTypes paymentType,
        address payer,
        address receiver,
        uint256 tokens,
        address dataService,
        uint256 dataServiceCut,
        address receiverDestination
    ) external override notPaused {
        _collectRouted(
            paymentType,
            payer,
            receiver,
            tokens,
            dataService,
            dataServiceCut,
            receiverDestination,
            bytes32(0)
        );
    }

    /// @inheritdoc IPaymentsEscrow
    function collect(
        IGraphPayments.PaymentTypes paymentType,
        address payer,
        address receiver,
        uint256 tokens,
        address dataService,
        uint256 dataServiceCut,
        address receiverDestination,
        bytes32 collectionContext
    ) external override notPaused {
        _collectRouted(
            paymentType,
            payer,
            receiver,
            tokens,
            dataService,
            dataServiceCut,
            receiverDestination,
            collectionContext
        );
    }

    /// @inheritdoc IPaymentsEscrow
    function getBalance(address payer, address collector, address receiver) external view override returns (uint256) {
        IPaymentsEscrow escrowOverride = escrowOverrides[payer];
        if (address(escrowOverride) != address(0)) {
            return escrowOverride.getBalance(payer, collector, receiver);
        }

        EscrowAccount storage account = escrowAccounts[payer][collector][receiver];
        return account.balance > account.tokensThawing ? account.balance - account.tokensThawing : 0;
    }

    // -- Internal --

    function _collectRouted(
        IGraphPayments.PaymentTypes _paymentType,
        address _payer,
        address _receiver,
        uint256 _tokens,
        address _dataService,
        uint256 _dataServiceCut,
        address _receiverDestination,
        bytes32 _collectionContext
    ) private {
        IPaymentsEscrow escrowOverride = escrowOverrides[_payer];
        if (address(escrowOverride) != address(0)) {
            escrowOverride.collect(
                _paymentType,
                _payer,
                _receiver,
                _tokens,
                _dataService,
                _dataServiceCut,
                _receiverDestination,
                _collectionContext
            );
            return;
        }

        // Standard escrow: deduct from own storage, distribute via GraphPayments
        EscrowAccount storage account = escrowAccounts[_payer][msg.sender][_receiver];
        require(account.balance >= _tokens, PaymentsEscrowInsufficientBalance(account.balance, _tokens));

        account.balance -= _tokens;

        uint256 escrowBalanceBefore = _graphToken().balanceOf(address(this));

        _graphToken().approve(address(_graphPayments()), _tokens);
        _graphPayments().collect(_paymentType, _receiver, _tokens, _dataService, _dataServiceCut, _receiverDestination);

        uint256 escrowBalanceAfter = _graphToken().balanceOf(address(this));
        require(
            escrowBalanceBefore == _tokens + escrowBalanceAfter,
            PaymentsEscrowInconsistentCollection(escrowBalanceBefore, escrowBalanceAfter, _tokens)
        );

        emit EscrowCollected(_paymentType, _payer, msg.sender, _receiver, _tokens, _receiverDestination);
    }

    function _onlyGovernor() internal view {
        require(msg.sender == _graphController().getGovernor(), EscrowRouterNotGovernor());
    }

    function _deposit(address _payer, address _collector, address _receiver, uint256 _tokens) private {
        escrowAccounts[_payer][_collector][_receiver].balance += _tokens;
        _graphToken().pullTokens(msg.sender, _tokens);
        emit Deposit(_payer, _collector, _receiver, _tokens);
    }
}
