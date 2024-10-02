// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { IGraphPayments } from "../../../contracts/interfaces/IGraphPayments.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

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

        _setOperator(users.operator, subgraphDataServiceAddress, true);
        resetPrank(users.operator);
        _stakeTo(users.indexer, operatorAmount);
        sp = staking.getServiceProvider(users.indexer);
        assertEq(sp.tokensStaked, amount + operatorAmount);
        assertEq(sp.tokensProvisioned, amount);
    }

    function testServiceProvider_SetDelegationFeeCut(
        uint256 feeCut,
        uint8 paymentTypeInput
    ) public useIndexer {
        vm.assume(paymentTypeInput < 3);
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes(paymentTypeInput);
        feeCut = bound(feeCut, 0, MAX_PPM);
        _setDelegationFeeCut(users.indexer, subgraphDataServiceAddress, paymentType, feeCut);
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

        _thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
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

        _thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
        tokensAvailable = staking.getTokensAvailable(users.indexer, subgraphDataServiceAddress, 0);
        assertEq(tokensAvailable, amount - thawAmount);
    }

    function testServiceProvider_GetTokensAvailable_WithDelegation(
        uint256 amount,
        uint256 delegationAmount,
        uint32 delegationRatio
    ) public useIndexer useProvision(amount, MAX_PPM, MAX_THAWING_PERIOD) useDelegation(delegationAmount) {
        uint256 tokensAvailable = staking.getTokensAvailable(users.indexer, subgraphDataServiceAddress, delegationRatio);

        uint256 tokensDelegatedMax = amount * (uint256(delegationRatio));
        uint256 tokensDelegatedCapacity = delegationAmount > tokensDelegatedMax ? tokensDelegatedMax : delegationAmount;
        assertEq(tokensAvailable, amount + tokensDelegatedCapacity);
    }

    function testServiceProvider_GetProviderTokensAvailable(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, MAX_PPM, MAX_THAWING_PERIOD) useDelegation(delegationAmount) {
        uint256 providerTokensAvailable = staking.getProviderTokensAvailable(users.indexer, subgraphDataServiceAddress);
        // Should not include delegated tokens
        assertEq(providerTokensAvailable, amount);
    }

    function testServiceProvider_HasStake(
        uint256 amount
    ) public useIndexer useProvision(amount, MAX_PPM, MAX_THAWING_PERIOD) {
        assertTrue(staking.hasStake(users.indexer));

        _thaw(users.indexer, subgraphDataServiceAddress, amount);
        skip(MAX_THAWING_PERIOD + 1);
        _deprovision(users.indexer, subgraphDataServiceAddress, 0);
        staking.unstake(amount);

        assertFalse(staking.hasStake(users.indexer));
    }

    function testServiceProvider_GetIndexerStakedTokens(
        uint256 amount
    ) public useIndexer useProvision(amount, MAX_PPM, MAX_THAWING_PERIOD) {
        assertEq(staking.getIndexerStakedTokens(users.indexer), amount);

        _thaw(users.indexer, subgraphDataServiceAddress, amount);
        // Does not discount thawing tokens
        assertEq(staking.getIndexerStakedTokens(users.indexer), amount);

        skip(MAX_THAWING_PERIOD + 1);
        _deprovision(users.indexer, subgraphDataServiceAddress, 0);
        // Does not discount thawing tokens
        assertEq(staking.getIndexerStakedTokens(users.indexer), amount);

        staking.unstake(amount);
        assertEq(staking.getIndexerStakedTokens(users.indexer), 0);
    }

    function testServiceProvider_RevertIf_InvalidDelegationFeeCut(
        uint256 cut,
        uint8 paymentTypeInput
    ) public useIndexer {
        vm.assume(paymentTypeInput < 3);
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes(paymentTypeInput);
        cut = bound(cut, MAX_PPM + 1, MAX_PPM + 100);
        vm.expectRevert(abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingInvalidDelegationFeeCut.selector,
            cut
        ));
        staking.setDelegationFeeCut(users.indexer, subgraphDataServiceAddress, paymentType, cut);
    }
}