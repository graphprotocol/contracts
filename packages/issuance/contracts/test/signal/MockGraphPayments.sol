// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.33;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";

/**
 * @title MockGraphPayments
 * @notice Minimal mock for testing IS escrow collect path.
 * Accepts collect() calls, transfers tokens from caller to receiver (no tax/cuts).
 */
contract MockGraphPayments {
    uint256 public collectCallCount;
    address public lastReceiver;
    uint256 public lastTokens;

    IERC20 public immutable graphToken;

    constructor(address _graphToken) {
        graphToken = IERC20(_graphToken);
    }

    function collect(
        IGraphPayments.PaymentTypes,
        address receiver,
        uint256 tokens,
        address,
        uint256,
        address
    ) external {
        collectCallCount++;
        lastReceiver = receiver;
        lastTokens = tokens;

        // Transfer tokens from caller (IS) to receiver (indexer)
        graphToken.transferFrom(msg.sender, receiver, tokens);
    }
}
