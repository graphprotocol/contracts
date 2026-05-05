// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { HorizonStakingSharedTest } from "../../shared/horizon-staking/HorizonStakingShared.t.sol";
import { DataServiceImpFees } from "../implementations/DataServiceImpFees.sol";
import { StakeClaims } from "../../../../contracts/data-service/libraries/StakeClaims.sol";
import { ProvisionTracker } from "../../../../contracts/data-service/libraries/ProvisionTracker.sol";
import { ILinkedList } from "@graphprotocol/interfaces/contracts/horizon/internal/ILinkedList.sol";

contract DataServiceFeesTest is HorizonStakingSharedTest {
    function test_Lock_RevertWhen_ZeroTokensAreLocked()
        external
        useIndexer
        useProvisionDataService(address(dataService), PROVISION_TOKENS, 0, 0)
    {
        vm.expectRevert(abi.encodeWithSignature("StakeClaimsZeroTokens()"));
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

        _assertLockStake(users.indexer, tokens);
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
            _assertLockStake(users.indexer, stepAmount);
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
        _assertLockStake(users.indexer, PROVISION_TOKENS / dataService.STAKE_TO_FEES_RATIO());

        // tryna lock some more
        uint256 additionalTokens = 10000;
        uint256 tokensRequired = dataService.feesProvisionTracker(users.indexer) +
            additionalTokens * dataService.STAKE_TO_FEES_RATIO();
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
        uint256 numClaimsToRelease
    ) external useIndexer useProvisionDataService(address(dataService), PROVISION_TOKENS, 0, 0) {
        // lock all provisioned stake in steps
        // limit tokens to at least 1 per step
        // limit steps to at least 15 so we stagger locks every 5 seconds to have some expired
        tokens = bound(tokens, 50, PROVISION_TOKENS / dataService.STAKE_TO_FEES_RATIO());
        steps = bound(steps, 15, 50);
        numClaimsToRelease = bound(numClaimsToRelease, 0, steps);

        uint256 stepAmount = tokens / steps;

        // lock tokens staggering the release
        for (uint256 i = 0; i < steps; i++) {
            _assertLockStake(users.indexer, stepAmount);
            vm.warp(block.timestamp + 5 seconds);
        }

        // it should release all expired claims
        _assertReleaseStake(users.indexer, numClaimsToRelease);
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
            _assertLockStake(users.indexer, stepAmount);
            vm.warp(block.timestamp + 5 seconds);
        }

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(ILinkedList.LinkedListInvalidIterations.selector));
        dataService.releaseStake(steps + 1);
    }

    // -- Assertion functions --
    // use struct to avoid 'stack too deep' error
    struct CalcValuesLockStake {
        uint256 unlockTimestamp;
        uint256 stakeToLock;
        bytes32 predictedClaimId;
    }
    function _assertLockStake(address serviceProvider, uint256 tokens) private {
        // before state
        (bytes32 beforeHead, , uint256 beforeNonce, uint256 beforeCount) = dataService.claimsLists(serviceProvider);
        uint256 beforeLockedStake = dataService.feesProvisionTracker(serviceProvider);

        // calc
        CalcValuesLockStake memory calcValues = CalcValuesLockStake({
            unlockTimestamp: block.timestamp + dataService.LOCK_DURATION(),
            stakeToLock: tokens * dataService.STAKE_TO_FEES_RATIO(),
            predictedClaimId: keccak256(abi.encodePacked(address(dataService), serviceProvider, beforeNonce))
        });

        // it should emit a an event
        vm.expectEmit();
        emit StakeClaims.StakeClaimLocked(
            serviceProvider,
            calcValues.predictedClaimId,
            calcValues.stakeToLock,
            calcValues.unlockTimestamp
        );
        dataService.lockStake(serviceProvider, tokens);

        // after state
        uint256 afterLockedStake = dataService.feesProvisionTracker(serviceProvider);
        (bytes32 afterHead, bytes32 afterTail, uint256 afterNonce, uint256 afterCount) = dataService.claimsLists(
            serviceProvider
        );

        // it should lock the tokens
        assertEq(beforeLockedStake + calcValues.stakeToLock, afterLockedStake);

        // it should create a stake claim
        (uint256 claimTokens, uint256 createdAt, uint256 releasableAt, bytes32 nextClaim) = dataService.claims(
            calcValues.predictedClaimId
        );
        assertEq(claimTokens, calcValues.stakeToLock);
        assertEq(createdAt, block.timestamp);
        assertEq(releasableAt, calcValues.unlockTimestamp);
        assertEq(nextClaim, bytes32(0));

        // it should update the list
        assertEq(afterCount, beforeCount + 1);
        assertEq(afterNonce, beforeNonce + 1);
        assertEq(afterHead, beforeCount == 0 ? calcValues.predictedClaimId : beforeHead);
        assertEq(afterTail, calcValues.predictedClaimId);
    }

    // use struct to avoid 'stack too deep' error
    struct CalcValuesReleaseStake {
        uint256 claimsCount;
        uint256 tokensReleased;
        bytes32 head;
    }
    function _assertReleaseStake(address serviceProvider, uint256 numClaimsToRelease) private {
        // before state
        (bytes32 beforeHead, bytes32 beforeTail, uint256 beforeNonce, uint256 beforeCount) = dataService.claimsLists(
            serviceProvider
        );
        uint256 beforeLockedStake = dataService.feesProvisionTracker(serviceProvider);

        // calc and set events
        vm.expectEmit();

        CalcValuesReleaseStake memory calcValues = CalcValuesReleaseStake({
            claimsCount: 0,
            tokensReleased: 0,
            head: beforeHead
        });
        while (
            calcValues.head != bytes32(0) && (calcValues.claimsCount < numClaimsToRelease || numClaimsToRelease == 0)
        ) {
            (uint256 claimTokens, , uint256 releasableAt, bytes32 nextClaim) = dataService.claims(calcValues.head);
            if (releasableAt > block.timestamp) {
                break;
            }

            emit StakeClaims.StakeClaimReleased(serviceProvider, calcValues.head, claimTokens, releasableAt);
            calcValues.head = nextClaim;
            calcValues.tokensReleased += claimTokens;
            calcValues.claimsCount++;
        }

        // it should emit a an event
        emit StakeClaims.StakeClaimsReleased(serviceProvider, calcValues.claimsCount, calcValues.tokensReleased);
        dataService.releaseStake(numClaimsToRelease);

        // after state
        (bytes32 afterHead, bytes32 afterTail, uint256 afterNonce, uint256 afterCount) = dataService.claimsLists(
            serviceProvider
        );
        uint256 afterLockedStake = dataService.feesProvisionTracker(serviceProvider);

        // it should release the tokens
        assertEq(beforeLockedStake - calcValues.tokensReleased, afterLockedStake);

        // it should remove the processed claims from the list
        assertEq(afterCount, beforeCount - calcValues.claimsCount);
        assertEq(afterNonce, beforeNonce);
        if (calcValues.claimsCount != 0) {
            assertNotEq(afterHead, beforeHead);
        } else {
            assertEq(afterHead, beforeHead);
        }
        assertEq(afterHead, calcValues.head);
        assertEq(afterTail, calcValues.claimsCount == beforeCount ? bytes32(0) : beforeTail);
    }
}
