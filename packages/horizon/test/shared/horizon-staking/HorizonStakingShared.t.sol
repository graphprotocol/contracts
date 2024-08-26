// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { GraphBaseTest } from "../../GraphBase.t.sol";
import { IGraphPayments } from "../../../contracts/interfaces/IGraphPayments.sol";
import { IHorizonStaking } from "../../../contracts/interfaces/IHorizonStaking.sol";
import { IHorizonStakingBase } from "../../../contracts/interfaces/internal/IHorizonStakingBase.sol";
import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";

import { MathUtils } from "../../../contracts/libraries/MathUtils.sol";

abstract contract HorizonStakingSharedTest is GraphBaseTest {
    /*
     * MODIFIERS
     */

    modifier useIndexer() {
        vm.startPrank(users.indexer);
        _;
        vm.stopPrank();
    }

    modifier useStake(uint256 amount) {
        vm.assume(amount > 0);
        _stake(amount);
        _;
    }

    modifier useProvision(
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) virtual {
        _useProvision(subgraphDataServiceAddress, tokens, maxVerifierCut, thawingPeriod);
        _;
    }

    modifier useProvisionDataService(
        address dataService,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) {
        _useProvision(dataService, tokens, maxVerifierCut, thawingPeriod);
        _;
    }

    modifier useDelegationFeeCut(IGraphPayments.PaymentTypes paymentType, uint256 cut) {
        _setDelegationFeeCut(paymentType, cut);
        _;
    }

    function _useProvision(address dataService, uint256 tokens, uint32 maxVerifierCut, uint64 thawingPeriod) internal {
        vm.assume(tokens <= MAX_STAKING_TOKENS);
        vm.assume(tokens > 0);
        vm.assume(maxVerifierCut <= MAX_MAX_VERIFIER_CUT);
        vm.assume(thawingPeriod <= MAX_THAWING_PERIOD);

        _createProvision(users.indexer, dataService, tokens, maxVerifierCut, thawingPeriod);
    }

    /*
     * HELPERS: these are shortcuts to perform common actions that often involve multiple contract calls
     */
    function _createProvision(
        address serviceProvider,
        address verifier,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) internal {
        _stakeTo(serviceProvider, tokens);
        _provision(serviceProvider, verifier, tokens, maxVerifierCut, thawingPeriod);
    }

    function _setDelegationFeeCut(IGraphPayments.PaymentTypes paymentType, uint256 cut) internal {
        staking.setDelegationFeeCut(users.indexer, subgraphDataServiceAddress, paymentType, cut);
        uint256 delegationFeeCut = staking.getDelegationFeeCut(users.indexer, subgraphDataServiceAddress, paymentType);
        assertEq(delegationFeeCut, cut);
    }

    /*
     * ACTIONS: these are individual contract calls wrapped in assertion blocks to ensure they work as expected
     */
    function _stake(uint256 tokens) internal {
        (, address msgSender, ) = vm.readCallers();
        _stakeTo(msgSender, tokens);
    }

    function _stakeTo(address serviceProvider, uint256 tokens) internal {
        (, address msgSender, ) = vm.readCallers();

        // before
        uint256 beforeStakingBalance = token.balanceOf(address(staking));
        uint256 beforeSenderBalance = token.balanceOf(msgSender);
        IHorizonStaking.ServiceProvider memory beforeServiceProvider = staking.getServiceProvider(serviceProvider);

        // stakeTo
        token.approve(address(staking), tokens);
        vm.expectEmit();
        emit IHorizonStakingBase.StakeDeposited(serviceProvider, tokens);
        staking.stakeTo(serviceProvider, tokens);

        // after
        uint256 afterStakingBalance = token.balanceOf(address(staking));
        uint256 afterSenderBalance = token.balanceOf(msgSender);
        IHorizonStaking.ServiceProvider memory afterServiceProvider = staking.getServiceProvider(serviceProvider);

        // assert
        assertEq(afterStakingBalance, beforeStakingBalance + tokens);
        assertEq(afterSenderBalance, beforeSenderBalance - tokens);
        assertEq(afterServiceProvider.tokensStaked, beforeServiceProvider.tokensStaked + tokens);
    }

    function _unstake(uint256 _tokens) internal {
        (, address msgSender, ) = vm.readCallers();

        uint256 deprecatedThawingPeriod = uint256(vm.load(address(staking), bytes32(uint256(13))));

        // before
        uint256 beforeSenderBalance = token.balanceOf(msgSender);
        uint256 beforeStakingBalance = token.balanceOf(address(staking));
        IHorizonStaking.ServiceProvider memory beforeServiceProvider = staking.getServiceProvider(msgSender);

        // unstake
        if (deprecatedThawingPeriod == 0) {
            vm.expectEmit(address(staking));
            emit IHorizonStakingMain.StakeWithdrawn(msgSender, _tokens);
            staking.unstake(_tokens);
        } else {
            // TODO
        }

        // after
        uint256 afterSenderBalance = token.balanceOf(msgSender);
        uint256 afterStakingBalance = token.balanceOf(address(staking));
        IHorizonStaking.ServiceProvider memory afterServiceProvider = staking.getServiceProvider(msgSender);

        // assert
        if (deprecatedThawingPeriod == 0) {
            assertEq(afterSenderBalance - beforeSenderBalance, _tokens);
            assertEq(afterStakingBalance, beforeStakingBalance - _tokens);
            assertEq(afterServiceProvider.tokensStaked, beforeServiceProvider.tokensStaked - _tokens);
        } else {
            // TODO
        }
    }

    function _unstakeDuringLockingPeriod(
        uint256 _tokens,
        uint256 _tokensStillThawing,
        uint256 _tokensToWithdraw,
        uint32 _oldLockingPeriod
    ) internal {
        uint256 previousIndexerTokens = token.balanceOf(users.indexer);
        uint256 previousIndexerIdleStake = staking.getIdleStake(users.indexer);

        vm.expectEmit(address(staking));
        uint256 lockingPeriod = block.number + THAWING_PERIOD_IN_BLOCKS;
        if (_tokensStillThawing > 0) {
            lockingPeriod =
                block.number +
                MathUtils.weightedAverageRoundingUp(
                    MathUtils.diffOrZero(_oldLockingPeriod, block.number),
                    _tokensStillThawing,
                    THAWING_PERIOD_IN_BLOCKS,
                    _tokens
                );
        }
        emit IHorizonStakingMain.StakeLocked(users.indexer, _tokens + _tokensStillThawing, lockingPeriod);
        staking.unstake(_tokens);

        uint256 idleStake = staking.getIdleStake(users.indexer);
        assertEq(idleStake, previousIndexerIdleStake - _tokens);

        uint256 newIndexerBalance = token.balanceOf(users.indexer);
        assertEq(newIndexerBalance - previousIndexerTokens, _tokensToWithdraw);
    }

    function _provision(
        address serviceProvider,
        address verifier,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) internal {
        // before
        IHorizonStaking.ServiceProvider memory beforeServiceProvider = staking.getServiceProvider(serviceProvider);

        // provision
        vm.expectEmit();
        emit IHorizonStakingMain.ProvisionCreated(serviceProvider, verifier, tokens, maxVerifierCut, thawingPeriod);
        staking.provision(serviceProvider, verifier, tokens, maxVerifierCut, thawingPeriod);

        // after
        IHorizonStaking.Provision memory afterProvision = staking.getProvision(serviceProvider, verifier);
        IHorizonStaking.ServiceProvider memory afterServiceProvider = staking.getServiceProvider(serviceProvider);

        // assert
        assertEq(afterProvision.tokens, tokens);
        assertEq(afterProvision.tokensThawing, 0);
        assertEq(afterProvision.sharesThawing, 0);
        assertEq(afterProvision.maxVerifierCut, maxVerifierCut);
        assertEq(afterProvision.thawingPeriod, thawingPeriod);
        assertEq(afterProvision.createdAt, uint64(block.timestamp));
        assertEq(afterProvision.maxVerifierCutPending, maxVerifierCut);
        assertEq(afterProvision.thawingPeriodPending, thawingPeriod);
        assertEq(afterServiceProvider.tokensProvisioned, tokens + beforeServiceProvider.tokensProvisioned);
    }
}
