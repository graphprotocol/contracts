// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IRewardsEligibilityEvents } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibilityEvents.sol";

import { RewardsEligibilityOracleSharedTest } from "./shared.t.sol";

/// @notice Tests for indexer eligibility renewal via the oracle.
contract RewardsEligibilityOracleIndexerManagementTest is RewardsEligibilityOracleSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function setUp() public override {
        super.setUp();
        _setupOracleRole();
    }

    // ==================== renewIndexerEligibility ====================

    function test_RenewSingleIndexer() public {
        _renewEligibility(indexer1);

        assertTrue(oracle.isEligible(indexer1));
        assertGt(oracle.getEligibilityRenewalTime(indexer1), 0);
    }

    function test_RenewMultipleIndexers() public {
        address[] memory indexers = new address[](2);
        indexers[0] = indexer1;
        indexers[1] = indexer2;

        vm.prank(oracleAccount);
        oracle.renewIndexerEligibility(indexers, "");

        assertTrue(oracle.isEligible(indexer1));
        assertTrue(oracle.isEligible(indexer2));
        assertGt(oracle.getEligibilityRenewalTime(indexer1), 0);
        assertGt(oracle.getEligibilityRenewalTime(indexer2), 0);
    }

    function test_RenewSameBlock_ReturnsZero() public {
        // First renewal
        _renewEligibility(indexer1);
        uint256 initialTime = oracle.getEligibilityRenewalTime(indexer1);

        // Same block — should return 0 updated
        address[] memory indexers = new address[](1);
        indexers[0] = indexer1;
        vm.prank(oracleAccount);
        uint256 count = oracle.renewIndexerEligibility(indexers, "");
        assertEq(count, 0);
        assertEq(oracle.getEligibilityRenewalTime(indexer1), initialTime);
    }

    function test_RenewNewBlock_ReturnsOne() public {
        _renewEligibility(indexer1);

        // Advance to next block
        vm.warp(block.timestamp + 1);

        address[] memory indexers = new address[](1);
        indexers[0] = indexer1;
        vm.prank(oracleAccount);
        uint256 count = oracle.renewIndexerEligibility(indexers, "");
        assertEq(count, 1);
    }

    function test_Revert_NonOracleCannotRenew() public {
        address[] memory indexers = new address[](1);
        indexers[0] = indexer1;

        vm.expectRevert();
        vm.prank(unauthorized);
        oracle.renewIndexerEligibility(indexers, "");
    }

    function test_ReturnCount_EmptyArray() public {
        address[] memory indexers = new address[](0);
        vm.prank(oracleAccount);
        uint256 count = oracle.renewIndexerEligibility(indexers, "");
        assertEq(count, 0);
    }

    function test_ReturnCount_SkipsZeroAddresses() public {
        address[] memory indexers = new address[](3);
        indexers[0] = indexer1;
        indexers[1] = address(0);
        indexers[2] = indexer2;

        vm.prank(oracleAccount);
        uint256 count = oracle.renewIndexerEligibility(indexers, "");
        assertEq(count, 2);
    }

    function test_ReturnCount_SkipsDuplicatesInSameBlock() public {
        address[] memory indexers = new address[](3);
        indexers[0] = indexer1;
        indexers[1] = indexer1; // duplicate
        indexers[2] = indexer2;

        vm.prank(oracleAccount);
        uint256 count = oracle.renewIndexerEligibility(indexers, "");
        // First indexer1 updates, second indexer1 is skipped (same block), indexer2 updates
        assertEq(count, 2);
    }

    function test_EmitsEvents() public {
        address[] memory indexers = new address[](1);
        indexers[0] = indexer1;

        vm.expectEmit(address(oracle));
        emit IRewardsEligibilityEvents.IndexerEligibilityData(oracleAccount, "");
        vm.expectEmit(address(oracle));
        emit IRewardsEligibilityEvents.IndexerEligibilityRenewed(indexer1, oracleAccount);

        vm.prank(oracleAccount);
        oracle.renewIndexerEligibility(indexers, "");
    }

    function test_UpdatesLastOracleUpdateTime() public {
        assertEq(oracle.getLastOracleUpdateTime(), 0);

        _renewEligibility(indexer1);
        assertEq(oracle.getLastOracleUpdateTime(), block.timestamp);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
