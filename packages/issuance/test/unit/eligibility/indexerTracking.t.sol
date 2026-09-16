// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Vm.sol";

import { IRewardsEligibilityEvents } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibilityEvents.sol";

import { RewardsEligibilityOracleSharedTest } from "./shared.t.sol";

/// @notice Tests for enumerable indexer tracking and staleness-based cleanup.
contract RewardsEligibilityOracleIndexerTrackingTest is RewardsEligibilityOracleSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function setUp() public override {
        super.setUp();
        _setupOracleRole();
    }

    // ==================== Tracking on Renewal ====================

    function test_Renewal_AddsToTrackedSet() public {
        assertEq(oracle.getIndexerCount(), 0);

        _renewEligibility(indexer1);

        assertEq(oracle.getIndexerCount(), 1);
        address[] memory indexers = oracle.getIndexers();
        assertEq(indexers.length, 1);
        assertEq(indexers[0], indexer1);
    }

    function test_Renewal_SecondIndexerIncreasesCount() public {
        _renewEligibility(indexer1);
        _renewEligibility(indexer2);

        assertEq(oracle.getIndexerCount(), 2);
        address[] memory indexers = oracle.getIndexers();
        assertEq(indexers.length, 2);
    }

    function test_Renewal_SameIndexerNoDuplicate() public {
        _renewEligibility(indexer1);
        assertEq(oracle.getIndexerCount(), 1);

        // Advance time so renewal actually updates timestamp
        vm.warp(block.timestamp + 1);
        _renewEligibility(indexer1);

        assertEq(oracle.getIndexerCount(), 1);
    }

    function test_Renewal_EmitsTrackingEvent_OnlyFirstTime() public {
        // First renewal — expect tracking event
        address[] memory indexers = new address[](1);
        indexers[0] = indexer1;

        vm.expectEmit(address(oracle));
        emit IRewardsEligibilityEvents.IndexerTrackingUpdated(indexer1, true);

        vm.prank(oracleAccount);
        oracle.renewIndexerEligibility(indexers, "");

        // Second renewal (new block) — no tracking event, only renewal event
        vm.warp(block.timestamp + 1);

        vm.recordLogs();
        vm.prank(oracleAccount);
        oracle.renewIndexerEligibility(indexers, "");

        // Check that no IndexerTrackingUpdated was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 trackingSig = keccak256("IndexerTrackingUpdated(address,bool)");
        for (uint256 i = 0; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != trackingSig, "unexpected IndexerTrackingUpdated event");
        }
    }

    // ==================== Pagination ====================

    function test_GetIndexers_Paginated() public {
        _renewEligibility(indexer1);
        _renewEligibility(indexer2);

        address[] memory all = oracle.getIndexers();
        assertEq(all.length, 2);

        address[] memory first = oracle.getIndexers(0, 1);
        assertEq(first.length, 1);
        assertEq(first[0], all[0]);

        address[] memory second = oracle.getIndexers(1, 1);
        assertEq(second.length, 1);
        assertEq(second[0], all[1]);
    }

    function test_GetIndexers_OffsetPastEnd_ReturnsEmpty() public {
        _renewEligibility(indexer1);

        address[] memory result = oracle.getIndexers(5, 10);
        assertEq(result.length, 0);
    }

    function test_GetIndexers_CountClamped() public {
        _renewEligibility(indexer1);

        address[] memory result = oracle.getIndexers(0, 100);
        assertEq(result.length, 1);
        assertEq(result[0], indexer1);
    }

    // ==================== Indexer Retention Period Configuration ====================

    function test_DefaultIndexerRetentionPeriod() public view {
        assertEq(oracle.getIndexerRetentionPeriod(), DEFAULT_INDEXER_RETENTION_PERIOD);
    }

    function test_SetIndexerRetentionPeriod() public {
        _setupOperatorRole();

        vm.expectEmit(address(oracle));
        emit IRewardsEligibilityEvents.IndexerRetentionPeriodSet(DEFAULT_INDEXER_RETENTION_PERIOD, 90 days);

        vm.prank(operator);
        bool result = oracle.setIndexerRetentionPeriod(90 days);
        assertTrue(result);

        assertEq(oracle.getIndexerRetentionPeriod(), 90 days);
    }

    function test_SetIndexerRetentionPeriod_SameValue_NoEvent() public {
        _setupOperatorRole();

        vm.recordLogs();
        vm.prank(operator);
        oracle.setIndexerRetentionPeriod(DEFAULT_INDEXER_RETENTION_PERIOD);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("IndexerRetentionPeriodSet(uint256,uint256)");
        for (uint256 i = 0; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != sig, "unexpected IndexerRetentionPeriodSet event");
        }
    }

    function test_Revert_SetIndexerRetentionPeriod_Unauthorized() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        oracle.setIndexerRetentionPeriod(90 days);
    }

    // ==================== Expired Indexer Removal ====================

    function test_RemoveExpiredIndexer_ReturnsFalse_WhenNotExpired() public {
        _renewEligibility(indexer1);

        bool gone = oracle.removeExpiredIndexer(indexer1);
        assertFalse(gone);
        assertEq(oracle.getIndexerCount(), 1);
    }

    function test_RemoveExpiredIndexer_ReturnsTrue_WhenExpired() public {
        _renewEligibility(indexer1);

        // Warp past retention period
        vm.warp(block.timestamp + DEFAULT_INDEXER_RETENTION_PERIOD);

        bool gone = oracle.removeExpiredIndexer(indexer1);
        assertTrue(gone);
        assertEq(oracle.getIndexerCount(), 0);
    }

    function test_RemoveExpiredIndexer_ReturnsTrue_WhenNotTracked() public {
        bool gone = oracle.removeExpiredIndexer(indexer1);
        assertTrue(gone);
    }

    function test_RemoveExpiredIndexer_DeletesTimestamp() public {
        _renewEligibility(indexer1);
        assertGt(oracle.getEligibilityRenewalTime(indexer1), 0);

        vm.warp(block.timestamp + DEFAULT_INDEXER_RETENTION_PERIOD);
        oracle.removeExpiredIndexer(indexer1);

        assertEq(oracle.getEligibilityRenewalTime(indexer1), 0);
    }

    function test_RemoveExpiredIndexer_EmitsEvent() public {
        _renewEligibility(indexer1);

        vm.warp(block.timestamp + DEFAULT_INDEXER_RETENTION_PERIOD);

        vm.expectEmit(address(oracle));
        emit IRewardsEligibilityEvents.IndexerTrackingUpdated(indexer1, false);

        oracle.removeExpiredIndexer(indexer1);
    }

    function test_RemoveExpiredIndexer_ReAddAfterRemoval() public {
        _renewEligibility(indexer1);

        vm.warp(block.timestamp + DEFAULT_INDEXER_RETENTION_PERIOD);
        oracle.removeExpiredIndexer(indexer1);
        assertEq(oracle.getIndexerCount(), 0);

        // Oracle renews the removed indexer — should re-add
        _renewEligibility(indexer1);
        assertEq(oracle.getIndexerCount(), 1);
        assertGt(oracle.getEligibilityRenewalTime(indexer1), 0);
    }

    function test_RemoveExpiredIndexer_Permissionless() public {
        _renewEligibility(indexer1);

        vm.warp(block.timestamp + DEFAULT_INDEXER_RETENTION_PERIOD);

        address anyone = makeAddr("anyone");
        vm.prank(anyone);
        bool gone = oracle.removeExpiredIndexer(indexer1);
        assertTrue(gone);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
