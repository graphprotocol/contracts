// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.27;

import { IndexingSignal } from "../../signal/IndexingSignal.sol";

/**
 * @title IndexingSignalTestHarness
 * @author Edge & Node
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
     * @param subgraphDeploymentID The subgraph deployment to collect from
     * @param indexer The indexer whose agreement escrow to collect from
     * @param amount The requested collection amount (0 for all available)
     * @return collectedTokens The amount of tokens collected
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
