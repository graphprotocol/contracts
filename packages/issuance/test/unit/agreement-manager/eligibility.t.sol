// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRewardsEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibility.sol";
import { IRecurringAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManager.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";
import { MockEligibilityOracle } from "./mocks/MockEligibilityOracle.sol";

/// @notice Tests for payment eligibility oracle in RecurringAgreementManager
contract RecurringAgreementManagerEligibilityTest is RecurringAgreementManagerSharedTest {
    MockEligibilityOracle internal oracle;

    function setUp() public override {
        super.setUp();
        oracle = new MockEligibilityOracle();
        vm.label(address(oracle), "EligibilityOracle");
    }

    /* solhint-disable graph/func-name-mixedcase */

    // -- setPaymentEligibilityOracle tests --

    function test_SetPaymentEligibilityOracle() public {
        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManager.PaymentEligibilityOracleSet(address(0), address(oracle));

        vm.prank(governor);
        agreementManager.setPaymentEligibilityOracle(address(oracle));
    }

    function test_SetPaymentEligibilityOracle_DisableWithZeroAddress() public {
        // First set an oracle
        vm.prank(governor);
        agreementManager.setPaymentEligibilityOracle(address(oracle));

        // Then disable it
        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManager.PaymentEligibilityOracleSet(address(oracle), address(0));

        vm.prank(governor);
        agreementManager.setPaymentEligibilityOracle(address(0));
    }

    function test_SetPaymentEligibilityOracle_Revert_WhenNotGovernor() public {
        vm.expectRevert();
        vm.prank(operator);
        agreementManager.setPaymentEligibilityOracle(address(oracle));
    }

    // -- isEligible passthrough tests --

    function test_IsEligible_TrueWhenNoOracle() public view {
        // No oracle set — all providers are eligible
        assertTrue(agreementManager.isEligible(indexer));
    }

    function test_IsEligible_DelegatesToOracle_WhenEligible() public {
        oracle.setEligible(indexer, true);

        vm.prank(governor);
        agreementManager.setPaymentEligibilityOracle(address(oracle));

        assertTrue(agreementManager.isEligible(indexer));
    }

    function test_IsEligible_DelegatesToOracle_WhenNotEligible() public {
        // indexer not set as eligible, default is false

        vm.prank(governor);
        agreementManager.setPaymentEligibilityOracle(address(oracle));

        assertFalse(agreementManager.isEligible(indexer));
    }

    function test_IsEligible_TrueAfterOracleDisabled() public {
        // Set oracle that denies indexer
        vm.prank(governor);
        agreementManager.setPaymentEligibilityOracle(address(oracle));
        assertFalse(agreementManager.isEligible(indexer));

        // Disable oracle
        vm.prank(governor);
        agreementManager.setPaymentEligibilityOracle(address(0));
        assertTrue(agreementManager.isEligible(indexer));
    }

    // -- ERC165 tests --

    function test_SupportsInterface_IRewardsEligibility() public view {
        assertTrue(agreementManager.supportsInterface(type(IRewardsEligibility).interfaceId));
    }

    /* solhint-enable graph/func-name-mixedcase */
}
