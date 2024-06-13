// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "forge-std/Console.sol";
import { HorizonStakingSharedTest } from "../../shared/horizon-staking/HorizonStakingShared.t.sol";
import { DataServiceImpFees } from "../implementations/DataServiceImpFees.sol";
import { IDataServiceFees } from "../../../contracts/data-service/interfaces/IDataServiceFees.sol";
import { ProvisionTracker } from "../../../contracts/data-service/libraries/ProvisionTracker.sol";
import { LinkedList } from "../../../contracts/libraries/LinkedList.sol";

contract DataServiceFeesTest is HorizonStakingSharedTest {
    function test_Lock_RevertWhen_ZeroTokensAreLocked()
        external
        useIndexer
        useProvisionDataService(address(dataService), PROVISION_TOKENS, 0, 0)
    {
        vm.expectRevert(abi.encodeWithSignature("DataServiceFeesZeroTokens()"));
        dataService.lockStake(users.indexer, 0);
    }

    uint256 public constant PROVISION_TOKENS = 10_000_000 ether;
    DataServiceImpFees dataService;

    function setUp() public override {
        super.setUp();

        dataService = new DataServiceImpFees(address(controller));
    }

    function test_Lock_WhenTheProvisionHasEnoughTokens(
        uint256 tokens
    ) external useIndexer useProvisionDataService(address(dataService), PROVISION_TOKENS, 0, 0) {
        tokens = bound(tokens, 1, PROVISION_TOKENS / dataService.STAKE_TO_FEES_RATIO());

        _assert_lockStake(users.indexer, tokens);
    }

    function test_Lock_WhenTheProvisionHasJustEnoughTokens(
        uint256 tokens,
        uint256 steps
    ) external useIndexer useProvisionDataService(address(dataService), PROVISION_TOKENS, 0, 0) {
        // lock all provisioned stake in steps
        // limit tokens to at least 1 per step
        tokens = bound(tokens, 50, PROVISION_TOKENS / dataService.STAKE_TO_FEES_RATIO());
        steps = bound(steps, 1, 50);
        uint256 stepAmount = tokens / steps;

        for (uint256 i = 0; i < steps; i++) {
            _assert_lockStake(users.indexer, stepAmount);
        }

        uint256 lockedStake = dataService.feesProvisionTracker(users.indexer);
        uint256 delta = (tokens % steps);
        assertEq(lockedStake, stepAmount * dataService.STAKE_TO_FEES_RATIO() * steps);
        assertEq(tokens * dataService.STAKE_TO_FEES_RATIO() - lockedStake, delta * dataService.STAKE_TO_FEES_RATIO());
    }

    function test_Lock_RevertWhen_TheProvisionHasNotEnoughTokens(
        uint256 tokens
    ) external useIndexer useProvisionDataService(address(dataService), PROVISION_TOKENS, 0, 0) {
        tokens = bound(tokens, 1, PROVISION_TOKENS / dataService.STAKE_TO_FEES_RATIO());

        // lock everything
        _assert_lockStake(users.indexer, PROVISION_TOKENS / dataService.STAKE_TO_FEES_RATIO());

        // tryna lock some more
        uint256 additionalTokens = 10000;
        uint256 tokensRequired = dataService.feesProvisionTracker(users.indexer) +
            additionalTokens *
            dataService.STAKE_TO_FEES_RATIO();
        uint256 tokensAvailable = staking.getTokensAvailable(users.indexer, address(dataService), 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProvisionTracker.ProvisionTrackerInsufficientTokens.selector,
                tokensAvailable,
                tokensRequired
            )
        );
        dataService.lockStake(users.indexer, additionalTokens);
    }

    function test_Release_WhenNIsValid(
        uint256 tokens,
        uint256 steps,
        uint256 n
    ) external useIndexer useProvisionDataService(address(dataService), PROVISION_TOKENS, 0, 0) {
        // lock all provisioned stake in steps
        // limit tokens to at least 1 per step
        // limit steps to at least 15 so we stagger locks every 5 seconds to have some expired
        tokens = bound(tokens, 50, PROVISION_TOKENS / dataService.STAKE_TO_FEES_RATIO());
        steps = bound(steps, 15, 50);
        n = bound(n, 0, steps);

        uint256 stepAmount = tokens / steps;

        // lock tokens staggering the release
        for (uint256 i = 0; i < steps; i++) {
            _assert_lockStake(users.indexer, stepAmount);
            vm.warp(block.timestamp + 5 seconds);
        }

        // it should release all expired claims
        _assert_releaseStake(users.indexer, n);
    }

    function test_Release_WhenNIsNotValid(
        uint256 tokens,
        uint256 steps
    ) external useIndexer useProvisionDataService(address(dataService), PROVISION_TOKENS, 0, 0) {
        // lock all provisioned stake in steps
        // limit tokens to at least 1 per step
        // limit steps to at least 15 so we stagger locks every 5 seconds to have some expired
        tokens = bound(tokens, 50, PROVISION_TOKENS / dataService.STAKE_TO_FEES_RATIO());
        steps = bound(steps, 15, 50);

        uint256 stepAmount = tokens / steps;

        // lock tokens staggering the release
        for (uint256 i = 0; i < steps; i++) {
            _assert_lockStake(users.indexer, stepAmount);
            vm.warp(block.timestamp + 5 seconds);
        }

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(LinkedList.LinkedListInvalidIterations.selector));
        dataService.releaseStake(steps + 1);
    }

    // -- Assertion functions --

    function _assert_lockStake(address serviceProvider, uint256 tokens) private {
        // before state
        (bytes32 beforeHead, , uint256 beforeNonce, uint256 beforeCount) = dataService.claimsLists(serviceProvider);
        uint256 beforeLockedStake = dataService.feesProvisionTracker(serviceProvider);

        // calc
        uint256 unlockTimestamp = block.timestamp + dataService.LOCK_DURATION();
        uint256 stakeToLock = tokens * dataService.STAKE_TO_FEES_RATIO();
        bytes32 predictedClaimId = keccak256(abi.encodePacked(address(dataService), serviceProvider, beforeNonce));

        // it should emit a an event
        vm.expectEmit();
        emit IDataServiceFees.StakeClaimLocked(serviceProvider, predictedClaimId, stakeToLock, unlockTimestamp);
        dataService.lockStake(serviceProvider, tokens);

        // after state
        uint256 afterLockedStake = dataService.feesProvisionTracker(serviceProvider);
        (bytes32 afterHead, bytes32 afterTail, uint256 afterNonce, uint256 afterCount) = dataService.claimsLists(
            serviceProvider
        );

        // it should lock the tokens
        assertEq(beforeLockedStake + stakeToLock, afterLockedStake);

        // it should create a stake claim
        (uint256 claimTokens, uint256 createdAt, uint256 releaseAt, bytes32 nextClaim) = dataService.claims(
            predictedClaimId
        );
        assertEq(claimTokens, stakeToLock);
        assertEq(createdAt, block.timestamp);
        assertEq(releaseAt, unlockTimestamp);
        assertEq(nextClaim, bytes32(0));

        // it should update the list
        assertEq(afterCount, beforeCount + 1);
        assertEq(afterNonce, beforeNonce + 1);
        assertEq(afterHead, beforeCount == 0 ? predictedClaimId : beforeHead);
        assertEq(afterTail, predictedClaimId);
    }

    function _assert_releaseStake(address serviceProvider, uint256 n) private {
        // before state
        (bytes32 beforeHead, bytes32 beforeTail, uint256 beforeNonce, uint256 beforeCount) = dataService.claimsLists(
            serviceProvider
        );
        uint256 beforeLockedStake = dataService.feesProvisionTracker(serviceProvider);

        // calc and set events
        vm.expectEmit();

        uint256 claimsCount = 0;
        uint256 tokensReleased = 0;
        bytes32 head = beforeHead;
        while (head != bytes32(0) && (claimsCount < n || n == 0)) {
            (uint256 claimTokens, , uint256 releaseAt, bytes32 nextClaim) = dataService.claims(head);
            if (releaseAt > block.timestamp) {
                break;
            }

            emit IDataServiceFees.StakeClaimReleased(serviceProvider, head, claimTokens, releaseAt);
            head = nextClaim;
            tokensReleased += claimTokens;
            claimsCount++;
        }

        // it should emit a an event
        emit IDataServiceFees.StakeClaimsReleased(serviceProvider, claimsCount, tokensReleased);
        dataService.releaseStake(n);

        // after state
        (bytes32 afterHead, bytes32 afterTail, uint256 afterNonce, uint256 afterCount) = dataService.claimsLists(
            serviceProvider
        );
        uint256 afterLockedStake = dataService.feesProvisionTracker(serviceProvider);

        // it should release the tokens
        assertEq(beforeLockedStake - tokensReleased, afterLockedStake);

        // it should remove the processed claims from the list
        assertEq(afterCount, beforeCount - claimsCount);
        assertEq(afterNonce, beforeNonce);
        if (claimsCount != 0) {
            assertNotEq(afterHead, beforeHead);
        } else {
            assertEq(afterHead, beforeHead);
        }
        assertEq(afterHead, head);
        assertEq(afterTail, claimsCount == beforeCount ? bytes32(0) : beforeTail);
    }
}
