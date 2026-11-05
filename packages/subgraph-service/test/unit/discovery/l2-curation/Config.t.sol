// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { DiscoveryTest } from "../shared/DiscoveryTest.t.sol";

contract ConfigTest is DiscoveryTest {
    uint32 internal constant MAX_PPM = 1_000_000;
    uint256 internal constant DEFAULT_MINIMUM_CURATION_DEPOSIT = 1;
    uint32 internal constant DEFAULT_CURATION_TAX_PERCENTAGE = 10_000;

    // -- defaultReserveRatio --

    function test_DefaultReserveRatio_FixedToMaxPPM() public view {
        assertEq(curation.defaultReserveRatio(), MAX_PPM);
    }

    function test_DefaultReserveRatio_RevertWhen_Set() public {
        vm.expectRevert(bytes("Not implemented in L2"));
        vm.prank(governor);
        curation.setDefaultReserveRatio(10);
    }

    // -- minimumCurationDeposit --

    function test_MinimumCurationDeposit_Set() public {
        assertEq(curation.minimumCurationDeposit(), DEFAULT_MINIMUM_CURATION_DEPOSIT);

        vm.prank(governor);
        curation.setMinimumCurationDeposit(100);
        assertEq(curation.minimumCurationDeposit(), 100);
    }

    function test_MinimumCurationDeposit_RevertWhen_Zero() public {
        vm.expectRevert(bytes("Minimum curation deposit cannot be 0"));
        vm.prank(governor);
        curation.setMinimumCurationDeposit(0);
    }

    function test_MinimumCurationDeposit_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(me);
        curation.setMinimumCurationDeposit(DEFAULT_MINIMUM_CURATION_DEPOSIT);
    }

    // -- curationTaxPercentage --

    function test_CurationTaxPercentage_Set() public {
        vm.startPrank(governor);
        curation.setCurationTaxPercentage(0);
        assertEq(curation.curationTaxPercentage(), 0);
        curation.setCurationTaxPercentage(DEFAULT_CURATION_TAX_PERCENTAGE);
        assertEq(curation.curationTaxPercentage(), DEFAULT_CURATION_TAX_PERCENTAGE);
        vm.stopPrank();
    }

    function test_CurationTaxPercentage_RevertWhen_OutOfBounds() public {
        vm.expectRevert(bytes("Curation tax percentage must be below or equal to MAX_PPM"));
        vm.prank(governor);
        curation.setCurationTaxPercentage(MAX_PPM + 1);
    }

    function test_CurationTaxPercentage_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(me);
        curation.setCurationTaxPercentage(0);
    }

    // -- curationTokenMaster --

    function test_CurationTokenMaster_Set() public {
        vm.prank(governor);
        curation.setCurationTokenMaster(address(curation));
        assertEq(curation.curationTokenMaster(), address(curation));
    }

    function test_CurationTokenMaster_RevertWhen_Empty() public {
        vm.expectRevert(bytes("Token master must be non-empty"));
        vm.prank(governor);
        curation.setCurationTokenMaster(address(0));
    }

    function test_CurationTokenMaster_RevertWhen_NotContract() public {
        vm.expectRevert(bytes("Token master must be a contract"));
        vm.prank(governor);
        curation.setCurationTokenMaster(makeAddr("notContract"));
    }

    function test_CurationTokenMaster_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(me);
        curation.setCurationTokenMaster(address(curation));
    }
}
