// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { RewardsEligibilityHelper } from "../../../contracts/eligibility/RewardsEligibilityHelper.sol";

import { RewardsEligibilityOracleSharedTest } from "./shared.t.sol";

/// @notice Tests for the stateless RewardsEligibilityHelper contract.
contract RewardsEligibilityHelperTest is RewardsEligibilityOracleSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    RewardsEligibilityHelper internal helper;

    function setUp() public override {
        super.setUp();
        _setupOracleRole();
        helper = new RewardsEligibilityHelper(address(oracle));
        vm.label(address(helper), "RewardsEligibilityHelper");
    }

    // ==================== Constructor ====================

    function test_Constructor_SetsOracle() public view {
        assertEq(helper.ORACLE(), address(oracle));
    }

    function test_Constructor_Revert_ZeroAddress() public {
        vm.expectRevert(RewardsEligibilityHelper.ZeroAddress.selector);
        new RewardsEligibilityHelper(address(0));
    }

    // ==================== Batch by Address List ====================

    function test_RemoveExpiredIndexers_List_AllExpired() public {
        _renewEligibility(indexer1);
        _renewEligibility(indexer2);

        vm.warp(block.timestamp + DEFAULT_INDEXER_RETENTION_PERIOD);

        address[] memory indexers = new address[](2);
        indexers[0] = indexer1;
        indexers[1] = indexer2;

        uint256 gone = helper.removeExpiredIndexers(indexers);
        assertEq(gone, 2);
        assertEq(oracle.getIndexerCount(), 0);
    }

    function test_RemoveExpiredIndexers_List_MixedExpiry() public {
        _renewEligibility(indexer1);

        // Advance time, then renew indexer2 (so only indexer1 is expired)
        vm.warp(block.timestamp + DEFAULT_INDEXER_RETENTION_PERIOD);
        _renewEligibility(indexer2);

        address[] memory indexers = new address[](2);
        indexers[0] = indexer1;
        indexers[1] = indexer2;

        uint256 gone = helper.removeExpiredIndexers(indexers);
        // indexer1 removed (gone), indexer2 still tracked (not expired)
        assertEq(gone, 1);
        assertEq(oracle.getIndexerCount(), 1);
    }

    function test_RemoveExpiredIndexers_List_IncludesUntracked() public {
        _renewEligibility(indexer1);

        vm.warp(block.timestamp + DEFAULT_INDEXER_RETENTION_PERIOD);

        address untracked = makeAddr("untracked");
        address[] memory indexers = new address[](2);
        indexers[0] = indexer1;
        indexers[1] = untracked;

        // Both are now absent — indexer1 removed, untracked was never there
        uint256 gone = helper.removeExpiredIndexers(indexers);
        assertEq(gone, 2);
    }

    function test_RemoveExpiredIndexers_List_Empty() public {
        address[] memory indexers = new address[](0);
        uint256 gone = helper.removeExpiredIndexers(indexers);
        assertEq(gone, 0);
    }

    // ==================== Batch All ====================

    function test_RemoveExpiredIndexers_All_AllExpired() public {
        _renewEligibility(indexer1);
        _renewEligibility(indexer2);

        vm.warp(block.timestamp + DEFAULT_INDEXER_RETENTION_PERIOD);

        uint256 gone = helper.removeExpiredIndexers();
        assertEq(gone, 2);
        assertEq(oracle.getIndexerCount(), 0);
    }

    function test_RemoveExpiredIndexers_All_MixedExpiry() public {
        _renewEligibility(indexer1);

        vm.warp(block.timestamp + DEFAULT_INDEXER_RETENTION_PERIOD);
        _renewEligibility(indexer2);

        uint256 gone = helper.removeExpiredIndexers();
        assertEq(gone, 1);
        assertEq(oracle.getIndexerCount(), 1);
    }

    function test_RemoveExpiredIndexers_All_NoneTracked() public {
        uint256 gone = helper.removeExpiredIndexers();
        assertEq(gone, 0);
    }

    // ==================== Batch by Paginated Scan ====================

    function test_RemoveExpiredIndexers_Scan_AllExpired() public {
        _renewEligibility(indexer1);
        _renewEligibility(indexer2);

        vm.warp(block.timestamp + DEFAULT_INDEXER_RETENTION_PERIOD);

        uint256 gone = helper.removeExpiredIndexers(0, 10);
        assertEq(gone, 2);
        assertEq(oracle.getIndexerCount(), 0);
    }

    function test_RemoveExpiredIndexers_Scan_MixedExpiry() public {
        _renewEligibility(indexer1);

        vm.warp(block.timestamp + DEFAULT_INDEXER_RETENTION_PERIOD);
        _renewEligibility(indexer2);

        // Both are tracked, but only indexer1 is expired
        uint256 gone = helper.removeExpiredIndexers(0, 10);
        assertEq(gone, 1);
        assertEq(oracle.getIndexerCount(), 1);
    }

    function test_RemoveExpiredIndexers_Scan_OffsetPastEnd() public {
        _renewEligibility(indexer1);

        vm.warp(block.timestamp + DEFAULT_INDEXER_RETENTION_PERIOD);

        uint256 gone = helper.removeExpiredIndexers(100, 10);
        assertEq(gone, 0);
        // indexer1 still tracked — scan didn't reach it
        assertEq(oracle.getIndexerCount(), 1);
    }

    function test_RemoveExpiredIndexers_Scan_PartialPage() public {
        _renewEligibility(indexer1);
        _renewEligibility(indexer2);

        vm.warp(block.timestamp + DEFAULT_INDEXER_RETENTION_PERIOD);

        // Only process first indexer
        uint256 gone = helper.removeExpiredIndexers(0, 1);
        assertEq(gone, 1);
        assertEq(oracle.getIndexerCount(), 1);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
