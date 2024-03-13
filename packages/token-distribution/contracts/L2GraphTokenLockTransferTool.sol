// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { L2GraphTokenLockManager } from "./L2GraphTokenLockManager.sol";
import { L2GraphTokenLockWallet } from "./L2GraphTokenLockWallet.sol";
import { ITokenGateway } from "./arbitrum/ITokenGateway.sol";

/**
 * @title L2GraphTokenLockTransferTool contract
 * @notice This contract is used to transfer GRT from L2 token lock wallets
 * back to their L1 counterparts.
 */
contract L2GraphTokenLockTransferTool {
    /// Address of the L2 GRT token
    IERC20 public immutable graphToken;
    /// Address of the L2GraphTokenGateway
    ITokenGateway public immutable l2Gateway;
    /// Address of the L1 GRT token (in L1, no aliasing)
    address public immutable l1GraphToken;

    /// @dev Emitted when GRT is sent to L1 from a token lock
    event LockedFundsSentToL1(
        address indexed l1Wallet,
        address indexed l2Wallet,
        address indexed l2LockManager,
        uint256 amount
    );

    /**
     * @notice Constructor for the L2GraphTokenLockTransferTool contract
     * @dev Note the L2GraphTokenLockTransferTool can be deployed behind a proxy,
     * and the constructor for the implementation will only set some immutable
     * variables.
     * @param _graphToken Address of the L2 GRT token
     * @param _l2Gateway Address of the L2GraphTokenGateway
     * @param _l1GraphToken Address of the L1 GRT token (in L1, no aliasing)
     */
    constructor(IERC20 _graphToken, ITokenGateway _l2Gateway, address _l1GraphToken) {
        graphToken = _graphToken;
        l2Gateway = _l2Gateway;
        l1GraphToken = _l1GraphToken;
    }

    /**
     * @notice Withdraw GRT from an L2 token lock wallet to its L1 counterpart.
     * This function must be called from an L2GraphTokenLockWallet contract.
     * The GRT will be sent to L1 and must be claimed using the Arbitrum Outbox on L1
     * after the standard Arbitrum withdrawal period (7 days).
     * @param _amount Amount of GRT to withdraw
     */
    function withdrawToL1Locked(uint256 _amount) external {
        L2GraphTokenLockWallet wallet = L2GraphTokenLockWallet(msg.sender);
        L2GraphTokenLockManager manager = L2GraphTokenLockManager(address(wallet.manager()));
        require(address(manager) != address(0), "INVALID_SENDER");
        address l1Wallet = manager.l2WalletToL1Wallet(msg.sender);
        require(l1Wallet != address(0), "NOT_L1_WALLET");
        require(_amount <= graphToken.balanceOf(msg.sender), "INSUFFICIENT_BALANCE");
        require(_amount != 0, "ZERO_AMOUNT");

        graphToken.transferFrom(msg.sender, address(this), _amount);
        graphToken.approve(address(l2Gateway), _amount);

        // Send the tokens through the L2GraphTokenGateway to the L1 wallet counterpart
        l2Gateway.outboundTransfer(l1GraphToken, l1Wallet, _amount, 0, 0, "");
        emit LockedFundsSentToL1(l1Wallet, msg.sender, address(manager), _amount);
    }
}
