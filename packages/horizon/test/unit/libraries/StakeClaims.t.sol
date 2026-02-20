// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { StakeClaims } from "../../../contracts/data-service/libraries/StakeClaims.sol";

contract StakeClaimsTest is Test {
    /* solhint-disable graph/func-name-mixedcase */

    function test_BuildStakeClaimId(address dataService, address serviceProvider, uint256 nonce) public pure {
        bytes32 id = StakeClaims.buildStakeClaimId(dataService, serviceProvider, nonce);
        bytes32 expectedId = keccak256(abi.encodePacked(dataService, serviceProvider, nonce));
        assertEq(id, expectedId, "StakeClaim ID does not match expected value");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
