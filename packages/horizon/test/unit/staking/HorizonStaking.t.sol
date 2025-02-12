// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";

import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStakingShared.t.sol";

contract HorizonStakingTest is HorizonStakingSharedTest {
    using stdStorage for StdStorage;

    /*
     * MODIFIERS
     */

    modifier usePausedStaking() {
        vm.startPrank(users.governor);
        controller.setPaused(true);
        vm.stopPrank();
        _;
    }

    modifier useThawAndDeprovision(uint256 amount, uint64 thawingPeriod) {
        vm.assume(amount > 0);
        _thaw(users.indexer, subgraphDataServiceAddress, amount);
        skip(thawingPeriod + 1);
        _deprovision(users.indexer, subgraphDataServiceAddress, 0);
        _;
    }

    modifier useDelegation(uint256 delegationAmount) {
        address msgSender;
        (, msgSender, ) = vm.readCallers();
        vm.assume(delegationAmount >= MIN_DELEGATION);
        vm.assume(delegationAmount <= MAX_STAKING_TOKENS);
        vm.startPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationAmount, 0);
        vm.startPrank(msgSender);
        _;
    }

    modifier useLockedVerifier(address verifier) {
        address msgSender;
        (, msgSender, ) = vm.readCallers();
        resetPrank(users.governor);
        _setAllowedLockedVerifier(verifier, true);
        resetPrank(msgSender);
        _;
    }

    modifier useDelegationSlashing() {
        address msgSender;
        (, msgSender, ) = vm.readCallers();
        resetPrank(users.governor);
        staking.setDelegationSlashingEnabled();
        resetPrank(msgSender);
        _;
    }

    modifier useUndelegate(uint256 shares) {
        resetPrank(users.delegator);

        DelegationPoolInternalTest memory pool = _getStorage_DelegationPoolInternal(
            users.indexer,
            subgraphDataServiceAddress,
            false
        );
        DelegationInternal memory delegation = _getStorage_Delegation(
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator,
            false
        );

        shares = bound(shares, 1, delegation.shares);
        uint256 tokens = (shares * (pool.tokens - pool.tokensThawing)) / pool.shares;
        if (shares < delegation.shares) {
            uint256 remainingTokens = (shares * (pool.tokens - pool.tokensThawing - tokens)) / pool.shares;
            vm.assume(remainingTokens >= MIN_DELEGATION);
        }

        _undelegate(users.indexer, subgraphDataServiceAddress, shares);
        _;
    }
}
