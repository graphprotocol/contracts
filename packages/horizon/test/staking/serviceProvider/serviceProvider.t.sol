// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";
import { IGraphPayments } from "../../../contracts/interfaces/IGraphPayments.sol";

contract HorizonStakingServiceProviderTest is HorizonStakingTest {

    /*
     * TESTS
     */

    function testServiceProvider_GetProvider(
        uint256 amount,
        uint256 operatorAmount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        operatorAmount = bound(operatorAmount, 1, MAX_STAKING_TOKENS);
        ServiceProvider memory sp = staking.getServiceProvider(users.indexer);
        assertEq(sp.tokensStaked, amount);
        assertEq(sp.tokensProvisioned, amount);

        staking.setOperator(users.operator, subgraphDataServiceAddress, true);
        resetPrank(users.operator);
        _stakeTo(users.indexer, operatorAmount);
        sp = staking.getServiceProvider(users.indexer);
        assertEq(sp.tokensStaked, amount + operatorAmount);
        assertEq(sp.tokensProvisioned, amount);
    }

    function testServiceProvider_GetDelegationFeeCut(
        uint256 queryCut,
        uint256 indexingCut,
        uint256 rewardsCut
    ) public useIndexer {
        _setDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, queryCut);
        _setDelegationFeeCut(IGraphPayments.PaymentTypes.IndexingFee, indexingCut);
        _setDelegationFeeCut(IGraphPayments.PaymentTypes.IndexingRewards, rewardsCut);

        uint256 queryFeeCut = staking.getDelegationFeeCut(users.indexer, subgraphDataServiceAddress, IGraphPayments.PaymentTypes.QueryFee);
        uint256 indexingFeeCut = staking.getDelegationFeeCut(users.indexer, subgraphDataServiceAddress, IGraphPayments.PaymentTypes.IndexingFee);
        uint256 indexingRewardsCut = staking.getDelegationFeeCut(users.indexer, subgraphDataServiceAddress, IGraphPayments.PaymentTypes.IndexingRewards);
        assertEq(queryFeeCut, queryCut);
        assertEq(indexingFeeCut, indexingCut);
        assertEq(indexingRewardsCut, rewardsCut);
    }

    function testServiceProvider_GetProvision(
        uint256 amount,
        uint256 thawAmount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        thawAmount = bound(thawAmount, 1, amount);
        Provision memory p = staking.getProvision(users.indexer, subgraphDataServiceAddress);
        assertEq(p.tokens, amount);
        assertEq(p.tokensThawing, 0);
        assertEq(p.sharesThawing, 0);
        assertEq(p.maxVerifierCut, maxVerifierCut);
        assertEq(p.thawingPeriod, thawingPeriod);
        assertEq(p.createdAt, block.timestamp);
        assertEq(p.maxVerifierCutPending, maxVerifierCut);
        assertEq(p.thawingPeriodPending, thawingPeriod);

        staking.thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
        p = staking.getProvision(users.indexer, subgraphDataServiceAddress);
        assertEq(p.tokensThawing, thawAmount);
    }

    function testServiceProvider_GetTokensAvailable(
        uint256 amount,
        uint256 thawAmount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        thawAmount = bound(thawAmount, 1, amount);
        uint256 tokensAvailable = staking.getTokensAvailable(users.indexer, subgraphDataServiceAddress, 0);
        assertEq(tokensAvailable, amount);

        staking.thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
        tokensAvailable = staking.getTokensAvailable(users.indexer, subgraphDataServiceAddress, 0);
        assertEq(tokensAvailable, amount - thawAmount);
    }

    function testServiceProvider_GetTokensAvailable_WithDelegation(
        uint256 amount,
        uint256 delegationAmount,
        uint32 delegationRatio
    ) public useIndexer useProvision(amount, MAX_MAX_VERIFIER_CUT, MAX_THAWING_PERIOD) useDelegation(delegationAmount) {
        uint256 tokensAvailable = staking.getTokensAvailable(users.indexer, subgraphDataServiceAddress, delegationRatio);

        uint256 tokensDelegatedMax = amount * (uint256(delegationRatio));
        uint256 tokensDelegatedCapacity = delegationAmount > tokensDelegatedMax ? tokensDelegatedMax : delegationAmount;
        assertEq(tokensAvailable, amount + tokensDelegatedCapacity);
    }

    function testServiceProvider_GetProviderTokensAvailable(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, MAX_MAX_VERIFIER_CUT, MAX_THAWING_PERIOD) useDelegation(delegationAmount) {
        uint256 providerTokensAvailable = staking.getProviderTokensAvailable(users.indexer, subgraphDataServiceAddress);
        assertEq(providerTokensAvailable, amount);
    }
}