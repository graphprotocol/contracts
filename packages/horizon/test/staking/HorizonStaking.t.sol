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
        vm.assume(delegationAmount > 1);
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
}
