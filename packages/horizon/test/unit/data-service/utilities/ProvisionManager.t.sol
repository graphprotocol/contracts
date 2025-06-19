// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";

import { ProvisionManager } from "../../../../contracts/data-service/utilities/ProvisionManager.sol";
import { IHorizonStakingTypes } from "../../../../contracts/interfaces/internal/IHorizonStakingTypes.sol";
import { PartialControllerMock } from "../../mocks/PartialControllerMock.t.sol";
import { HorizonStakingMock } from "../../mocks/HorizonStakingMock.t.sol";
import { ProvisionManagerImpl } from "./ProvisionManagerImpl.t.sol";

contract ProvisionManagerTest is Test {
    ProvisionManagerImpl internal _provisionManager;
    HorizonStakingMock internal _horizonStakingMock;

    function setUp() public {
        _horizonStakingMock = new HorizonStakingMock();

        PartialControllerMock.Entry[] memory entries = new PartialControllerMock.Entry[](1);
        entries[0] = PartialControllerMock.Entry({ name: "Staking", addr: address(_horizonStakingMock) });
        _provisionManager = new ProvisionManagerImpl(address(new PartialControllerMock(entries)));
    }

    /* solhint-disable graph/func-name-mixedcase */

    function test_OnlyValidProvision(address serviceProvider) public {
        vm.expectRevert(
            abi.encodeWithSelector(ProvisionManager.ProvisionManagerProvisionNotFound.selector, serviceProvider)
        );
        _provisionManager.onlyValidProvision_(serviceProvider);

        IHorizonStakingTypes.Provision memory provision;
        provision.createdAt = 1;

        _horizonStakingMock.setProvision(serviceProvider, address(_provisionManager), provision);

        _provisionManager.onlyValidProvision_(serviceProvider);
    }

    function test_OnlyAuthorizedForProvision(address serviceProvider, address sender) public {
        vm.expectRevert(
            abi.encodeWithSelector(ProvisionManager.ProvisionManagerNotAuthorized.selector, serviceProvider, sender)
        );
        vm.prank(sender);
        _provisionManager.onlyAuthorizedForProvision_(serviceProvider);

        _horizonStakingMock.setIsAuthorized(serviceProvider, address(_provisionManager), sender, true);
        vm.prank(sender);
        _provisionManager.onlyAuthorizedForProvision_(serviceProvider);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
