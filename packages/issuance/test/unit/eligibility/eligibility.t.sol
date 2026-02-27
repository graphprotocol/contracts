// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { RewardsEligibilityOracleSharedTest } from "./shared.t.sol";

/// @notice Tests for the isEligible view function and its various conditions.
contract RewardsEligibilityOracleEligibilityTest is RewardsEligibilityOracleSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function setUp() public override {
        super.setUp();
        _setupOracleRole();
    }

    // ==================== Validation Disabled ====================

    function test_AllEligible_WhenValidationDisabled() public view {
        // Validation disabled by default — all indexers eligible
        assertTrue(oracle.isEligible(indexer1));
        assertTrue(oracle.isEligible(indexer2));
        assertTrue(oracle.isEligible(unauthorized));
    }

    // ==================== Oracle Timeout ====================

    function test_AllEligible_WhenOracleTimeoutExceeded() public {
        _enableValidation();

        // Set non-zero lastOracleUpdateTime
        _renewEligibility(unauthorized);

        // Set short timeout
        vm.prank(operator);
        oracle.setOracleUpdateTimeout(60);

        // indexer1 was never renewed — should be ineligible before timeout
        assertFalse(oracle.isEligible(indexer1));

        // Advance past timeout
        vm.warp(block.timestamp + 120);

        // Now all indexers are eligible (oracle timeout exceeded)
        assertTrue(oracle.isEligible(indexer1));
    }

    // ==================== Normal Eligibility Flow ====================

    function test_IneligibleBeforeRenewal() public {
        _enableValidation();
        _renewEligibility(unauthorized); // set lastOracleUpdateTime

        assertFalse(oracle.isEligible(indexer1));
    }

    function test_EligibleAfterRenewal() public {
        _enableValidation();
        _renewEligibility(unauthorized); // set lastOracleUpdateTime
        _renewEligibility(indexer1);

        assertTrue(oracle.isEligible(indexer1));
    }

    function test_IneligibleAfterPeriodExpires() public {
        _enableValidation();
        _renewEligibility(indexer1);

        // Set short eligibility period
        vm.prank(operator);
        oracle.setEligibilityPeriod(60);

        // Still eligible
        assertTrue(oracle.isEligible(indexer1));

        // Advance past eligibility period
        vm.warp(block.timestamp + 120);

        assertFalse(oracle.isEligible(indexer1));
    }

    function test_EligibleAfterReRenewal() public {
        _enableValidation();
        _renewEligibility(indexer1);

        // Set short period and expire
        vm.prank(operator);
        oracle.setEligibilityPeriod(60);
        vm.warp(block.timestamp + 120);
        assertFalse(oracle.isEligible(indexer1));

        // Re-renew
        _renewEligibility(indexer1);
        assertTrue(oracle.isEligible(indexer1));
    }

    // ==================== Edge Cases ====================

    function test_NeverRegisteredIndexerEligible_WhenPeriodExceedsTimestamp() public {
        // TRST-L-1: When eligibilityPeriod > block.timestamp, all indexers become eligible
        // because block.timestamp < 0 + eligibilityPeriod
        _enableValidation();
        _renewEligibility(unauthorized); // set lastOracleUpdateTime

        // Normal period: never-registered indexer is ineligible
        assertEq(oracle.getEligibilityRenewalTime(indexer1), 0);
        assertFalse(oracle.isEligible(indexer1));

        // Set period larger than current timestamp
        uint256 largePeriod = block.timestamp + 365 days;
        vm.prank(operator);
        oracle.setEligibilityPeriod(largePeriod);

        // Now never-registered indexer is eligible: block.timestamp < 0 + largePeriod
        assertTrue(oracle.isEligible(indexer1));
        assertTrue(oracle.isEligible(indexer2));
    }

    function test_RenewalTimeZero_ForNeverRenewedIndexer() public view {
        assertEq(oracle.getEligibilityRenewalTime(indexer1), 0);
    }

    function test_RenewalTimeCorrect_AfterRenewal() public {
        _setupOracleRole();
        _renewEligibility(indexer1);
        assertEq(oracle.getEligibilityRenewalTime(indexer1), block.timestamp);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
