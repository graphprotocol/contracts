// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { GraphDirectory } from "@graphprotocol/horizon/contracts/utilities/GraphDirectory.sol";
import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { DisputeManager } from "../../../../../contracts/DisputeManager.sol";
import { DisputeManagerTest } from "../DisputeManager.t.sol";
import { IDisputeManager } from "../../../../../contracts/interfaces/IDisputeManager.sol";

contract DisputeManagerConstructorTest is DisputeManagerTest {
    using PPMMath for uint256;

    /*
     * MODIFIERS
     */

    modifier useDeployer() {
        vm.startPrank(users.deployer);
        _;
        vm.stopPrank();
    }

    /*
     * HELPERS
     */

    function _initializeDisputeManager(
        address implementation,
        address arbitrator,
        uint64 disputePeriod,
        uint256 disputeDeposit,
        uint32 fishermanRewardPercentage,
        uint32 maxSlashingPercentage
    ) private returns (address) {
        return
            UnsafeUpgrades.deployTransparentProxy(
                implementation,
                users.governor,
                abi.encodeCall(
                    DisputeManager.initialize,
                    (
                        users.deployer,
                        arbitrator,
                        disputePeriod,
                        disputeDeposit,
                        fishermanRewardPercentage,
                        maxSlashingPercentage
                    )
                )
            );
    }

    /*
     * TESTS
     */

    function test_DisputeManager_Constructor(
        uint32 fishermanRewardPercentage,
        uint32 maxSlashingPercentage
    ) public useDeployer {
        vm.assume(fishermanRewardPercentage <= disputeManager.MAX_FISHERMAN_REWARD_CUT());
        vm.assume(maxSlashingPercentage <= PPMMath.MAX_PPM);
        address disputeManagerImplementation = address(new DisputeManager(address(controller)));
        address proxy = _initializeDisputeManager(
            disputeManagerImplementation,
            users.arbitrator,
            disputePeriod,
            disputeDeposit,
            fishermanRewardPercentage,
            maxSlashingPercentage
        );

        DisputeManager disputeManager = DisputeManager(proxy);
        assertEq(disputeManager.arbitrator(), users.arbitrator);
        assertEq(disputeManager.disputePeriod(), disputePeriod);
        assertEq(disputeManager.disputeDeposit(), disputeDeposit);
        assertEq(disputeManager.fishermanRewardCut(), fishermanRewardPercentage);
    }

    function test_DisputeManager_Constructor_RevertIf_ControllerAddressIsZero() public useDeployer {
        bytes memory expectedError = abi.encodeWithSelector(
            GraphDirectory.GraphDirectoryInvalidZeroAddress.selector,
            "Controller"
        );
        vm.expectRevert(expectedError);
        new DisputeManager(address(0));
    }

    function test_DisputeManager_Constructor_RevertIf_ArbitratorAddressIsZero() public useDeployer {
        address disputeManagerImplementation = address(new DisputeManager(address(controller)));
        bytes memory expectedError = abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidZeroAddress.selector);
        vm.expectRevert(expectedError);
        _initializeDisputeManager(
            disputeManagerImplementation,
            address(0),
            disputePeriod,
            disputeDeposit,
            fishermanRewardPercentage,
            maxSlashingPercentage
        );
    }

    function test_DisputeManager_Constructor_RevertIf_InvalidDisputePeriod() public useDeployer {
        address disputeManagerImplementation = address(new DisputeManager(address(controller)));
        bytes memory expectedError = abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputePeriodZero.selector);
        vm.expectRevert(expectedError);
        _initializeDisputeManager(
            disputeManagerImplementation,
            users.arbitrator,
            0,
            disputeDeposit,
            fishermanRewardPercentage,
            maxSlashingPercentage
        );
    }

    function test_DisputeManager_Constructor_RevertIf_InvalidDisputeDeposit() public useDeployer {
        address disputeManagerImplementation = address(new DisputeManager(address(controller)));
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidDisputeDeposit.selector,
            0
        );
        vm.expectRevert(expectedError);
        _initializeDisputeManager(
            disputeManagerImplementation,
            users.arbitrator,
            disputePeriod,
            0,
            fishermanRewardPercentage,
            maxSlashingPercentage
        );
    }

    function test_DisputeManager_Constructor_RevertIf_InvalidFishermanRewardPercentage(
        uint32 _fishermanRewardPercentage
    ) public useDeployer {
        vm.assume(_fishermanRewardPercentage > disputeManager.MAX_FISHERMAN_REWARD_CUT());
        address disputeManagerImplementation = address(new DisputeManager(address(controller)));
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidFishermanReward.selector,
            _fishermanRewardPercentage
        );
        vm.expectRevert(expectedError);
        _initializeDisputeManager(
            disputeManagerImplementation,
            users.arbitrator,
            disputePeriod,
            disputeDeposit,
            _fishermanRewardPercentage,
            maxSlashingPercentage
        );
    }

    function test_DisputeManager_Constructor_RevertIf_InvalidMaxSlashingPercentage(
        uint32 _maxSlashingPercentage
    ) public useDeployer {
        vm.assume(_maxSlashingPercentage > PPMMath.MAX_PPM);
        address disputeManagerImplementation = address(new DisputeManager(address(controller)));
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidMaxSlashingCut.selector,
            _maxSlashingPercentage
        );
        vm.expectRevert(expectedError);
        _initializeDisputeManager(
            disputeManagerImplementation,
            users.arbitrator,
            disputePeriod,
            disputeDeposit,
            fishermanRewardPercentage,
            _maxSlashingPercentage
        );
    }
}
