// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.33;

import { IndexingSignal } from "../../signal/IndexingSignal.sol";

/**
 * @title IndexingSignalTestHarness
 * @notice Exposes internal functions for white-box testing.
 */
contract IndexingSignalTestHarness is IndexingSignal {
    constructor(
        address graphToken,
        address rewardsManager,
        address curation,
        address escrowRouter,
        address graphPayments
    ) IndexingSignal(graphToken, rewardsManager, curation, escrowRouter, graphPayments) {}

    /**
     * @notice Test-only: collect virtual issuance and mint to caller.
     * Replaces the removed direct collect() for testing purposes.
     */
    function collectTest(
        bytes32 subgraphDeploymentID,
        address indexer,
        uint256 amount
    ) external returns (uint256 collectedTokens) {
        collectedTokens = _collectVirtual(subgraphDeploymentID, indexer, amount);

        if (collectedTokens > 0) {
            GRAPH_TOKEN.mint(msg.sender, collectedTokens);
        }

        emit IssuanceCollected(subgraphDeploymentID, indexer, collectedTokens);
    }
}
