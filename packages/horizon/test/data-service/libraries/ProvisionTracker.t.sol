// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { HorizonStakingSharedTest } from "../../shared/horizon-staking/HorizonStakingShared.t.sol";
import { ProvisionTrackerImplementation } from "./ProvisionTrackerImplementation.sol";
import { ProvisionTracker } from "../../../contracts/data-service/libraries/ProvisionTracker.sol";
import { IHorizonStaking } from "./../../../contracts/interfaces/IHorizonStaking.sol";

// Wrapper required because when using vm.expectRevert, the error is expected in the next immediate call
// Which in the case of this library is an internal call to the staking contract
// See: https://github.com/foundry-rs/foundry/issues/5454
library ProvisionTrackerWrapper {
    function lock(
        mapping(address => uint256) storage self,
        IHorizonStaking graphStaking,
        address serviceProvider,
        uint256 tokens,
        uint32 delegationRatio
    ) external {
        ProvisionTracker.lock(self, graphStaking, serviceProvider, tokens, delegationRatio);
    }

    function release(mapping(address => uint256) storage self, address serviceProvider, uint256 tokens) external {
        ProvisionTracker.release(self, serviceProvider, tokens);
    }
}

contract ProvisionTrackerTest is HorizonStakingSharedTest, ProvisionTrackerImplementation {
    using ProvisionTrackerWrapper for mapping(address => uint256);

    function test_Lock_GivenTheProvisionHasSufficientAvailableTokens(
        uint256 tokens,
        uint256 steps
    ) external useIndexer useProvisionDataService(address(this), tokens, 0, 0) {
        vm.assume(tokens > 0);
        vm.assume(steps > 0);
        vm.assume(steps < 100);
        uint256 stepAmount = tokens / steps;

        for (uint256 i = 0; i < steps; i++) {
            uint256 beforeLockedAmount = provisionTracker[users.indexer];
            provisionTracker.lock(staking, users.indexer, stepAmount, uint32(0));
            uint256 afterLockedAmount = provisionTracker[users.indexer];
            assertEq(afterLockedAmount, beforeLockedAmount + stepAmount);
        }

        assertEq(provisionTracker[users.indexer], stepAmount * steps);
        uint256 delta = (tokens % steps);
        uint256 tokensAvailable = staking.getTokensAvailable(users.indexer, address(this), 0);
        assertEq(tokensAvailable - provisionTracker[users.indexer], delta);
    }

    function test_Lock_RevertGiven_TheProvisionHasInsufficientAvailableTokens(
        uint256 tokens
    ) external useIndexer useProvisionDataService(address(this), tokens, 0, 0) {
        uint256 tokensToLock = tokens + 1;
        vm.expectRevert(
            abi.encodeWithSelector(ProvisionTracker.ProvisionTrackerInsufficientTokens.selector, tokens, tokensToLock)
        );
        provisionTracker.lock(staking, users.indexer, tokensToLock, uint32(0));
    }

    function test_Release_GivenTheProvisionHasSufficientLockedTokens(
        uint256 tokens,
        uint256 steps
    ) external useIndexer useProvisionDataService(address(this), tokens, 0, 0) {
        vm.assume(tokens > 0);
        vm.assume(steps > 0);
        vm.assume(steps < 100);

        // setup
        provisionTracker.lock(staking, users.indexer, tokens, uint32(0));

        // lock entire provision, then unlock in steps
        uint256 stepAmount = tokens / steps;

        for (uint256 i = 0; i < steps; i++) {
            uint256 beforeLockedAmount = provisionTracker[users.indexer];
            provisionTracker.release(users.indexer, stepAmount);
            uint256 afterLockedAmount = provisionTracker[users.indexer];
            assertEq(afterLockedAmount, beforeLockedAmount - stepAmount);
        }

        assertEq(provisionTracker[users.indexer], tokens - stepAmount * steps);
        uint256 delta = (tokens % steps);
        assertEq(provisionTracker[users.indexer], delta);
    }

    function test_Release_RevertGiven_TheProvisionHasInsufficientLockedTokens(uint256 tokens) external useIndexer useProvisionDataService(address(this), tokens, 0, 0) {
        // setup
        provisionTracker.lock(staking, users.indexer, tokens, uint32(0));

        uint256 tokensToRelease = tokens + 1;
        vm.expectRevert(
            abi.encodeWithSelector(ProvisionTracker.ProvisionTrackerInsufficientTokens.selector, tokens, tokensToRelease)
        );
        provisionTracker.release(users.indexer, tokensToRelease);
    }
}
