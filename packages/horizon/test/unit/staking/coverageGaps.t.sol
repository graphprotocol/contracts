// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";
import { IHorizonStakingBase } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingBase.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";

import { HorizonStakingTest } from "./HorizonStaking.t.sol";

/// @notice Tests targeting uncovered view functions in HorizonStakingBase.sol
contract HorizonStakingCoverageGapsTest is HorizonStakingTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ══════════════════════════════════════════════════════════════════════
    //  getSubgraphService (L56-57)
    // ══════════════════════════════════════════════════════════════════════

    function test_GetSubgraphService() public view {
        address subgraphService = staking.getSubgraphService();
        assertEq(subgraphService, subgraphDataServiceLegacyAddress);
    }

    // ══════════════════════════════════════════════════════════════════════
    //  getIdleStake (L76-77)
    // ══════════════════════════════════════════════════════════════════════

    function test_GetIdleStake_NoStake() public view {
        uint256 idleStake = staking.getIdleStake(users.indexer);
        assertEq(idleStake, 0);
    }

    function test_GetIdleStake_WithStake(
        uint256 stakeAmount,
        uint256 provisionAmount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(stakeAmount, maxVerifierCut, thawingPeriod) {
        // All staked tokens are provisioned, so idle = 0
        uint256 idleStake = staking.getIdleStake(users.indexer);
        assertEq(idleStake, 0);
    }

    // ══════════════════════════════════════════════════════════════════════
    //  getDelegation (L98, L103-106)
    // ══════════════════════════════════════════════════════════════════════

    function test_GetDelegation_NoDelegation() public view {
        Delegation memory delegation = staking.getDelegation(
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator
        );
        assertEq(delegation.shares, 0);
    }

    function test_GetDelegation_WithDelegation(
        uint256 stakeAmount,
        uint256 delegationAmount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(stakeAmount, maxVerifierCut, thawingPeriod) useDelegation(delegationAmount) {
        Delegation memory delegation = staking.getDelegation(
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator
        );
        assertGt(delegation.shares, 0);
    }

    // ══════════════════════════════════════════════════════════════════════
    //  getThawedTokens early return when no thaw requests (L181)
    // ══════════════════════════════════════════════════════════════════════

    function test_GetThawedTokens_ZeroRequests_Delegation(
        uint256 stakeAmount,
        uint256 delegationAmount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(stakeAmount, maxVerifierCut, thawingPeriod) useDelegation(delegationAmount) {
        // Delegator has delegation shares but no thaw requests
        uint256 thawedTokens = staking.getThawedTokens(
            IHorizonStakingTypes.ThawRequestType.Delegation,
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator
        );
        assertEq(thawedTokens, 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
