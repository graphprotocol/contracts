// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { GraphBaseTest } from "../../GraphBase.t.sol";
import { DataServiceImpPausableUpgradeable } from "../implementations/DataServiceImpPausableUpgradeable.sol";
import { IDataServicePausable } from "@graphprotocol/interfaces/contracts/data-service/IDataServicePausable.sol";
import { UnsafeUpgrades } from "@openzeppelin/foundry-upgrades/src/Upgrades.sol";

import { PPMMath } from "./../../../../contracts/libraries/PPMMath.sol";

contract DataServicePausableUpgradeableTest is GraphBaseTest {
    DataServiceImpPausableUpgradeable private dataService;

    function setUp() public override {
        super.setUp();
        (dataService, ) = _deployDataService();
    }

    function test_WhenTheContractIsDeployed() external view {
        // via proxy - ensure that the proxy was initialized correctly
        // these calls validate proxy storage was correctly initialized
        uint32 delegationRatio = dataService.getDelegationRatio();
        assertEq(delegationRatio, type(uint32).max);

        (uint256 minTokens, uint256 maxTokens) = dataService.getProvisionTokensRange();
        assertEq(minTokens, type(uint256).min);
        assertEq(maxTokens, type(uint256).max);

        (uint32 minVerifierCut, uint32 maxVerifierCut) = dataService.getVerifierCutRange();
        assertEq(minVerifierCut, type(uint32).min);
        assertEq(maxVerifierCut, uint32(PPMMath.MAX_PPM));

        (uint64 minThawingPeriod, uint64 maxThawingPeriod) = dataService.getThawingPeriodRange();
        assertEq(minThawingPeriod, type(uint64).min);
        assertEq(maxThawingPeriod, type(uint64).max);
    }

    // -- setPauseGuardian --

    function test_SetPauseGuardian() external {
        address guardian = makeAddr("guardian");

        vm.expectEmit(address(dataService));
        emit IDataServicePausable.PauseGuardianSet(guardian, true);
        dataService.setPauseGuardian(guardian, true);

        assertTrue(dataService.pauseGuardians(guardian));
    }

    function test_SetPauseGuardian_Remove() external {
        address guardian = makeAddr("guardian");
        dataService.setPauseGuardian(guardian, true);

        vm.expectEmit(address(dataService));
        emit IDataServicePausable.PauseGuardianSet(guardian, false);
        dataService.setPauseGuardian(guardian, false);

        assertFalse(dataService.pauseGuardians(guardian));
    }

    function test_RevertWhen_SetPauseGuardian_NoChange_AlreadyFalse() external {
        address guardian = makeAddr("guardian");

        // guardian defaults to false, setting to false should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDataServicePausable.DataServicePausablePauseGuardianNoChange.selector,
                guardian,
                false
            )
        );
        dataService.setPauseGuardian(guardian, false);
    }

    function test_RevertWhen_SetPauseGuardian_NoChange_AlreadyTrue() external {
        address guardian = makeAddr("guardian");
        dataService.setPauseGuardian(guardian, true);

        // guardian is already true, setting to true should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDataServicePausable.DataServicePausablePauseGuardianNoChange.selector,
                guardian,
                true
            )
        );
        dataService.setPauseGuardian(guardian, true);
    }

    // -- pause --

    function test_Pause() external {
        address guardian = makeAddr("guardian");
        dataService.setPauseGuardian(guardian, true);

        vm.prank(guardian);
        dataService.pause();

        assertTrue(dataService.paused());
    }

    function test_RevertWhen_Pause_NotGuardian() external {
        address notGuardian = makeAddr("notGuardian");

        vm.expectRevert(
            abi.encodeWithSelector(IDataServicePausable.DataServicePausableNotPauseGuardian.selector, notGuardian)
        );
        vm.prank(notGuardian);
        dataService.pause();
    }

    // -- unpause --

    function test_Unpause() external {
        address guardian = makeAddr("guardian");
        dataService.setPauseGuardian(guardian, true);

        vm.startPrank(guardian);
        dataService.pause();
        dataService.unpause();
        vm.stopPrank();

        assertFalse(dataService.paused());
    }

    function test_RevertWhen_Unpause_NotGuardian() external {
        address guardian = makeAddr("guardian");
        dataService.setPauseGuardian(guardian, true);

        vm.prank(guardian);
        dataService.pause();

        address notGuardian = makeAddr("notGuardian");
        vm.expectRevert(
            abi.encodeWithSelector(IDataServicePausable.DataServicePausableNotPauseGuardian.selector, notGuardian)
        );
        vm.prank(notGuardian);
        dataService.unpause();
    }

    // -- helpers --

    function _deployDataService()
        internal
        returns (DataServiceImpPausableUpgradeable, DataServiceImpPausableUpgradeable)
    {
        // Deploy implementation
        address implementation = address(new DataServiceImpPausableUpgradeable(address(controller)));

        // Deploy proxy
        address proxy = UnsafeUpgrades.deployTransparentProxy(
            implementation,
            users.governor,
            abi.encodeCall(DataServiceImpPausableUpgradeable.initialize, ())
        );

        return (DataServiceImpPausableUpgradeable(proxy), DataServiceImpPausableUpgradeable(implementation));
    }
}
