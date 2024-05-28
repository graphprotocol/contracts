// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { DataS } from "./DataS.sol";

// import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStaking.t.sol";

contract DataServiceTest is Test {
    DataS ds = new DataS();
    address sp1 = makeAddr("sp1");

    function setUp() public {
        ds.lockStake(sp1, 10 wei, block.timestamp + 100);
        ds.lockStake(sp1, 1 wei, block.timestamp + 200);
        ds.lockStake(sp1, 1 wei, block.timestamp + 300);
        ds.lockStake(sp1, 1 wei, block.timestamp + 400);
        vm.warp(block.timestamp + 2000);
        console.log("done setup");
    }

    function test_test() public {
        assertTrue(true);
    }

    function test_release() public {
        ds.releaseStake2(sp1, 0);
    }
}
