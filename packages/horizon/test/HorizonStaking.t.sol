// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { HorizonStaking } from "../contracts/HorizonStaking.sol";
import { ControllerMock } from "../contracts/mocks/ControllerMock.sol";
import { HorizonStakingExtension } from "../contracts/HorizonStakingExtension.sol";
import { ExponentialRebates } from "../contracts/utils/ExponentialRebates.sol";

contract HorizonStakingTest is Test {
    ExponentialRebates rebates;
    HorizonStakingExtension ext;
    HorizonStaking staking;
    ControllerMock controller;

    function setUp() public {
        console.log("Deploying Controller mock");
        controller = new ControllerMock(address(0x1));
        console.log("Deploying HorizonStaking");
        rebates = new ExponentialRebates();
        ext = new HorizonStakingExtension(address(controller), address(0x1), address(rebates));
        staking = new HorizonStaking(address(controller), address(ext), address(0x1));
    }

    function test_MinimumDelegationConstant() public view {
        assertEq(staking.MINIMUM_DELEGATION(), 1e18);
    }
}
