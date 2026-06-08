// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";
import { IProviderEligibilityManagement } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibilityManagement.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";
import { MockEligibilityOracle } from "./mocks/MockEligibilityOracle.sol";

/// @notice Tests for payment eligibility oracle in RecurringAgreementManager
contract RecurringAgreementManagerEligibilityTest is RecurringAgreementManagerSharedTest {
    MockEligibilityOracle internal oracle;
    IProviderEligibility internal constant NO_ORACLE = IProviderEligibility(address(0));

    function setUp() public override {
        super.setUp();
        oracle = new MockEligibilityOracle();
        vm.label(address(oracle), "EligibilityOracle");
    }

    /* solhint-disable graph/func-name-mixedcase */

    // -- setProviderEligibilityOracle tests --

    function test_SetPaymentEligibilityOracle() public {
        vm.expectEmit(address(agreementManager));
        emit IProviderEligibilityManagement.ProviderEligibilityOracleSet(NO_ORACLE, oracle);

        vm.prank(governor);
        agreementManager.setProviderEligibilityOracle(oracle);
    }

    function test_SetPaymentEligibilityOracle_DisableWithZeroAddress() public {
        // First set an oracle
        vm.prank(governor);
        agreementManager.setProviderEligibilityOracle(oracle);

        // Then disable it
        vm.expectEmit(address(agreementManager));
        emit IProviderEligibilityManagement.ProviderEligibilityOracleSet(oracle, NO_ORACLE);

        vm.prank(governor);
        agreementManager.setProviderEligibilityOracle(NO_ORACLE);
    }

    function test_SetPaymentEligibilityOracle_NoopWhenSameOracle() public {
        // Set oracle
        vm.prank(governor);
        agreementManager.setProviderEligibilityOracle(oracle);

        // Set same oracle again — early return, no event
        vm.prank(governor);
        agreementManager.setProviderEligibilityOracle(oracle);

        // Oracle still works (confirms state unchanged)
        oracle.setEligible(indexer, true);
        assertTrue(agreementManager.isEligible(indexer));
    }

    function test_SetPaymentEligibilityOracle_Revert_WhenNotGovernor() public {
        vm.expectRevert();
        vm.prank(operator);
        agreementManager.setProviderEligibilityOracle(oracle);
    }

    function test_GetProviderEligibilityOracle_ReturnsZeroByDefault() public view {
        assertEq(address(agreementManager.getProviderEligibilityOracle()), address(0));
    }

    function test_GetProviderEligibilityOracle_ReturnsSetOracle() public {
        vm.prank(governor);
        agreementManager.setProviderEligibilityOracle(oracle);
        assertEq(address(agreementManager.getProviderEligibilityOracle()), address(oracle));
    }

    // -- isEligible passthrough tests --

    function test_IsEligible_TrueWhenNoOracle() public view {
        // No oracle set — all providers are eligible
        assertTrue(agreementManager.isEligible(indexer));
    }

    function test_IsEligible_DelegatesToOracle_WhenEligible() public {
        oracle.setEligible(indexer, true);

        vm.prank(governor);
        agreementManager.setProviderEligibilityOracle(oracle);

        assertTrue(agreementManager.isEligible(indexer));
    }

    function test_IsEligible_DelegatesToOracle_WhenNotEligible() public {
        // indexer not set as eligible, default is false

        vm.prank(governor);
        agreementManager.setProviderEligibilityOracle(oracle);

        assertFalse(agreementManager.isEligible(indexer));
    }

    function test_IsEligible_TrueAfterOracleDisabled() public {
        // Set oracle that denies indexer
        vm.prank(governor);
        agreementManager.setProviderEligibilityOracle(oracle);
        assertFalse(agreementManager.isEligible(indexer));

        // Disable oracle
        vm.prank(governor);
        agreementManager.setProviderEligibilityOracle(NO_ORACLE);
        assertTrue(agreementManager.isEligible(indexer));
    }

    // -- ERC165 tests --

    function test_SupportsInterface_IProviderEligibility() public view {
        assertTrue(agreementManager.supportsInterface(type(IProviderEligibility).interfaceId));
    }

    /* solhint-enable graph/func-name-mixedcase */
}
