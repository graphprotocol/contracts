// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IHorizonStakingMain } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingMain.sol";
import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";
import { ILinkedList } from "@graphprotocol/interfaces/contracts/horizon/internal/ILinkedList.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

/**
 * @title HorizonStakingReleaseThawedDelegationTest
 * @notice Tests for {releaseThawedDelegation} and the released-but-not-withdrawn (withdrawable) accounting.
 * @dev The core invariants under test:
 *  - releasing is permissionless and idempotent, and never reverts on "nothing to do";
 *  - releasing only re-buckets per-delegator bookkeeping: it does NOT change the actively-earning base
 *    ({getDelegatedTokensAvailable}) nor remove tokens from the slashable thawing pool;
 *  - released tokens remain fully slashable (no slash-evasion, no pool-brick underflow);
 *  - a full slash invalidates released shares via the thawing nonce.
 */
contract HorizonStakingReleaseThawedDelegationTest is HorizonStakingTest {
    /*
     * HELPERS
     */

    function _undelegateAll() private returns (uint256 sharesThawing) {
        DelegationInternal memory delegation = _getStorageDelegation(
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator,
            false
        );
        resetPrank(users.delegator);
        _undelegate(users.indexer, subgraphDataServiceAddress, delegation.shares);
        DelegationPoolInternalTest memory pool = _getStorageDelegationPoolInternal(
            users.indexer,
            subgraphDataServiceAddress,
            false
        );
        return pool.sharesThawing;
    }

    /*
     * TESTS
     */

    /// @notice Releasing does not change the actively-earning base; it only re-buckets bookkeeping.
    function testRelease_DoesNotChangeActiveBase(
        uint256 delegationAmount,
        uint256 undelegateShares
    )
        public
        useIndexer
        useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD)
        useDelegation(delegationAmount)
        useUndelegate(undelegateShares)
    {
        skip(MAX_THAWING_PERIOD + 1);

        uint256 activeBefore = staking.getDelegatedTokensAvailable(users.indexer, subgraphDataServiceAddress);

        resetPrank(users.delegator);
        staking.releaseThawedDelegation(users.indexer, subgraphDataServiceAddress, users.delegator, 0);

        uint256 activeAfter = staking.getDelegatedTokensAvailable(users.indexer, subgraphDataServiceAddress);
        assertEq(activeAfter, activeBefore, "release must not change the actively-earning base");
    }

    /// @notice Anyone may release another delegator's matured thaw requests, and it surfaces as withdrawable.
    function testRelease_Permissionless(
        uint256 delegationAmount
    )
        public
        useIndexer
        useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD)
        useDelegation(delegationAmount)
        useUndelegate(type(uint256).max)
    {
        skip(MAX_THAWING_PERIOD + 1);

        DelegationPoolInternalTest memory poolBefore = _getStorageDelegationPoolInternal(
            users.indexer,
            subgraphDataServiceAddress,
            false
        );
        assertEq(poolBefore.sharesWithdrawable, 0);
        assertEq(staking.getDelegatedTokensWithdrawable(users.indexer, subgraphDataServiceAddress), 0);

        // A random third party (not the delegator) performs the housekeeping.
        address keeper = makeAddr("keeper");
        resetPrank(keeper);
        staking.releaseThawedDelegation(users.indexer, subgraphDataServiceAddress, users.delegator, 0);

        DelegationPoolInternalTest memory poolAfter = _getStorageDelegationPoolInternal(
            users.indexer,
            subgraphDataServiceAddress,
            false
        );
        DelegationInternal memory delegation = _getStorageDelegation(
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator,
            false
        );

        assertEq(poolAfter.sharesWithdrawable, poolBefore.sharesThawing, "all matured shares released");
        assertEq(delegation.sharesWithdrawable, poolBefore.sharesThawing);
        assertEq(delegation.withdrawableThawingNonce, poolAfter.thawingNonce);
        // The thawing pool totals are untouched - tokens stay slashable.
        assertEq(poolAfter.tokensThawing, poolBefore.tokensThawing);
        assertEq(poolAfter.sharesThawing, poolBefore.sharesThawing);
        // Withdrawable token-equivalent equals the full thawing balance (single delegator).
        assertEq(
            staking.getDelegatedTokensWithdrawable(users.indexer, subgraphDataServiceAddress),
            poolBefore.tokensThawing
        );
    }

    /// @notice Releasing before the thaw period elapses is a no-op that does not revert.
    function testRelease_NoOpWhenNotMatured(
        uint256 delegationAmount
    )
        public
        useIndexer
        useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD)
        useDelegation(delegationAmount)
        useUndelegate(type(uint256).max)
    {
        resetPrank(users.delegator);
        uint256 released = staking.releaseThawedDelegation(
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator,
            0
        );
        assertEq(released, 0, "nothing matured -> zero released, no revert");
        assertEq(staking.getDelegatedTokensWithdrawable(users.indexer, subgraphDataServiceAddress), 0);
    }

    /// @notice Releasing with no thaw requests at all is a no-op that does not revert.
    function testRelease_NoOpWhenNoRequests(
        uint256 delegationAmount
    ) public useIndexer useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD) useDelegation(delegationAmount) {
        resetPrank(users.delegator);
        uint256 released = staking.releaseThawedDelegation(
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator,
            0
        );
        assertEq(released, 0);
    }

    /// @notice After an external release, the delegator can still withdraw even though the request list is empty.
    function testRelease_ThenWithdrawByDelegator(
        uint256 delegationAmount
    )
        public
        useIndexer
        useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD)
        useDelegation(delegationAmount)
        useUndelegate(type(uint256).max)
    {
        skip(MAX_THAWING_PERIOD + 1);

        // Third-party release empties the thaw request list.
        address keeper = makeAddr("keeper");
        resetPrank(keeper);
        staking.releaseThawedDelegation(users.indexer, subgraphDataServiceAddress, users.delegator, 0);

        ILinkedList.List memory list = staking.getThawRequestList(
            IHorizonStakingTypes.ThawRequestType.Delegation,
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator
        );
        assertEq(list.count, 0, "release consumed the thaw requests");

        uint256 expected = staking.getDelegatedTokensWithdrawable(users.indexer, subgraphDataServiceAddress);
        uint256 balanceBefore = token.balanceOf(users.delegator);

        // Withdraw must succeed off the pre-released shares (list is empty).
        resetPrank(users.delegator);
        staking.withdrawDelegated(users.indexer, subgraphDataServiceAddress, 0);

        assertEq(token.balanceOf(users.delegator) - balanceBefore, expected, "withdraws the released balance");
        DelegationInternal memory delegation = _getStorageDelegation(
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator,
            false
        );
        assertEq(delegation.sharesWithdrawable, 0, "withdrawable cleared after withdraw");
    }

    /// @notice CRITICAL: released-but-not-withdrawn delegation remains fully slashable (no slash-evasion).
    function testRelease_ReleasedTokensRemainSlashable()
        public
        useIndexer
        useProvision(1000 ether, 0, MAX_THAWING_PERIOD)
        useDelegationSlashing
    {
        uint256 delegationTokens = 1000 ether;
        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);

        // Undelegate everything so the whole delegation is thawing.
        _undelegateAll();
        skip(MAX_THAWING_PERIOD + 1);

        // Release: the delegator "banks" the matured thaw into the withdrawable bucket.
        resetPrank(users.delegator);
        staking.releaseThawedDelegation(users.indexer, subgraphDataServiceAddress, users.delegator, 0);
        assertEq(
            staking.getDelegatedTokensWithdrawable(users.indexer, subgraphDataServiceAddress),
            delegationTokens,
            "fully withdrawable after release"
        );

        // Now slash. Provision (1000) is consumed first, then 400 of delegation is burned.
        uint256 delegationSlash = 400 ether;
        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, 1000 ether + delegationSlash, 0);

        // The released tokens were NOT exempt: the withdrawable balance scaled down with the slash.
        uint256 expectedRemaining = delegationTokens - delegationSlash; // 600 ether
        assertEq(
            staking.getDelegatedTokensWithdrawable(users.indexer, subgraphDataServiceAddress),
            expectedRemaining,
            "released bucket is slashed proportionally"
        );

        // Views never underflow / brick the pool.
        assertEq(staking.getDelegatedTokensAvailable(users.indexer, subgraphDataServiceAddress), 0);

        // Withdrawing nets only the post-slash amount - the slash was borne, not evaded.
        uint256 balanceBefore = token.balanceOf(users.delegator);
        resetPrank(users.delegator);
        staking.withdrawDelegated(users.indexer, subgraphDataServiceAddress, 0);
        assertEq(
            token.balanceOf(users.delegator) - balanceBefore,
            expectedRemaining,
            "delegator withdraws the slashed amount, not the pre-slash amount"
        );
    }

    /// @notice Releasing before a slash yields the same outcome as not releasing (releasing buys no protection).
    function testRelease_NoSlashEvasionAdvantage()
        public
        useIndexer
        useProvision(1000 ether, 0, MAX_THAWING_PERIOD)
        useDelegationSlashing
    {
        uint256 delegationTokens = 1000 ether;
        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);
        _undelegateAll();
        skip(MAX_THAWING_PERIOD + 1);

        // Path A: release THEN slash.
        resetPrank(users.delegator);
        staking.releaseThawedDelegation(users.indexer, subgraphDataServiceAddress, users.delegator, 0);

        uint256 delegationSlash = 250 ether;
        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, 1000 ether + delegationSlash, 0);

        uint256 balanceBefore = token.balanceOf(users.delegator);
        resetPrank(users.delegator);
        staking.withdrawDelegated(users.indexer, subgraphDataServiceAddress, 0);
        uint256 withdrawnAfterRelease = token.balanceOf(users.delegator) - balanceBefore;

        // The control (no release before slash) is exercised by the existing withdraw tests; here we assert the
        // economically meaningful property directly: a released delegator still loses exactly the slashed share.
        assertEq(withdrawnAfterRelease, delegationTokens - delegationSlash, "no protection gained by releasing early");
    }

    /// @notice A full slash bumps the thawing nonce and invalidates released shares; withdraw nets zero, no revert.
    function testRelease_FullSlashInvalidatesReleasedShares()
        public
        useIndexer
        useProvision(1000 ether, 0, MAX_THAWING_PERIOD)
        useDelegationSlashing
    {
        uint256 delegationTokens = 1000 ether;
        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);
        _undelegateAll();
        skip(MAX_THAWING_PERIOD + 1);

        resetPrank(users.delegator);
        staking.releaseThawedDelegation(users.indexer, subgraphDataServiceAddress, users.delegator, 0);

        DelegationPoolInternalTest memory poolBeforeSlash = _getStorageDelegationPoolInternal(
            users.indexer,
            subgraphDataServiceAddress,
            false
        );

        // Slash the entire provision + delegation.
        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, 1000 ether + delegationTokens, 0);

        DelegationPoolInternalTest memory poolAfterSlash = _getStorageDelegationPoolInternal(
            users.indexer,
            subgraphDataServiceAddress,
            false
        );
        assertEq(poolAfterSlash.tokensThawing, 0, "thawing tokens fully burned");
        assertEq(poolAfterSlash.sharesThawing, 0, "thawing shares reset");
        assertEq(poolAfterSlash.sharesWithdrawable, 0, "withdrawable shares reset");
        assertEq(poolAfterSlash.thawingNonce, poolBeforeSlash.thawingNonce + 1, "nonce bumped");

        // Withdrawable view returns zero (no thawing shares left), no division-by-zero.
        assertEq(staking.getDelegatedTokensWithdrawable(users.indexer, subgraphDataServiceAddress), 0);

        // Withdraw is a clean no-op: stale shares are invalidated by the nonce, nothing transferred, no revert.
        uint256 balanceBefore = token.balanceOf(users.delegator);
        resetPrank(users.delegator);
        staking.withdrawDelegated(users.indexer, subgraphDataServiceAddress, 0);
        assertEq(token.balanceOf(users.delegator), balanceBefore, "fully slashed -> nothing to withdraw");
    }

    /// @notice The withdrawable view returns zero when the pool has no thawing shares.
    function testGetDelegatedTokensWithdrawable_ZeroWhenNoThawing(
        uint256 delegationAmount
    ) public useIndexer useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD) useDelegation(delegationAmount) {
        assertEq(staking.getDelegatedTokensWithdrawable(users.indexer, subgraphDataServiceAddress), 0);
    }

    /// @notice Releasing twice is idempotent - the second call finds nothing to release.
    function testRelease_Idempotent(
        uint256 delegationAmount
    )
        public
        useIndexer
        useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD)
        useDelegation(delegationAmount)
        useUndelegate(type(uint256).max)
    {
        skip(MAX_THAWING_PERIOD + 1);
        resetPrank(users.delegator);
        uint256 first = staking.releaseThawedDelegation(users.indexer, subgraphDataServiceAddress, users.delegator, 0);
        assertGt(first, 0);
        uint256 second = staking.releaseThawedDelegation(users.indexer, subgraphDataServiceAddress, users.delegator, 0);
        assertEq(second, 0, "second release is a no-op");
    }
}
