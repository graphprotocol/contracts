// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";

/**
 * @title MockGraphPayments
 * @author Edge & Node
 * @notice Minimal mock for testing IS escrow collect path.
 * Accepts collect() calls, transfers tokens from caller to receiver (no tax/cuts).
 */
contract MockGraphPayments {
    /// @notice Number of times collect has been called
    uint256 public collectCallCount;
    /// @notice The receiver address from the last collect call
    address public lastReceiver;
    /// @notice The token amount from the last collect call
    uint256 public lastTokens;

    /// @notice The Graph Token contract
    IERC20 public immutable GRAPH_TOKEN;

    /// @notice Constructor for MockGraphPayments
    /// @param graphToken Address of the Graph Token contract
    constructor(address graphToken) {
        GRAPH_TOKEN = IERC20(graphToken);
    }

    /// @notice Collect tokens from caller and transfer to receiver
    /// @param receiver The address receiving the tokens
    /// @param tokens The amount of tokens to transfer
    // solhint-disable-next-line use-natspec
    function collect(
        IGraphPayments.PaymentTypes,
        address receiver,
        uint256 tokens,
        address,
        uint256,
        address
    ) external {
        ++collectCallCount;
        lastReceiver = receiver;
        lastTokens = tokens;

        // Transfer tokens from caller (IS) to receiver (indexer)
        require(GRAPH_TOKEN.transferFrom(msg.sender, receiver, tokens));
    }
}
