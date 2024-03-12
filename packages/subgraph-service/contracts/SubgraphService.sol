// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.4.0 <0.9.0;

import {Test} from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";

contract SimpleTest is Test {
    function test() external pure returns (uint256) {
        return 42;
    }
}
