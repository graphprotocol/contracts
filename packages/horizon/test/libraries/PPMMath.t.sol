// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { PPMMath } from "../../contracts/libraries/PPMMath.sol";

contract PPMMathTest is Test {
    uint32 private constant MAX_PPM = 1000000;

    function test_mulPPM(uint256 a, uint256 b) public pure {
        a = bound(a, 0, MAX_PPM);
        b = bound(b, 0, type(uint256).max / MAX_PPM);

        uint256 result = PPMMath.mulPPM(a, b);
        assertEq(result, (a * b) / MAX_PPM);
    }

    function test_mulPPMRoundUp(uint256 a, uint256 b) public pure {
        a = bound(a, 0, type(uint256).max / MAX_PPM);
        b = bound(b, 0, MAX_PPM);

        uint256 result = PPMMath.mulPPMRoundUp(a, b);
        assertEq(result, a - PPMMath.mulPPM(a, MAX_PPM - b));
    }

    function test_isValidPPM(uint256 value) public pure {
        bool result = PPMMath.isValidPPM(value);
        assert(result == (value <= MAX_PPM));
    }

    function test_mullPPM_RevertWhen_InvalidPPM(uint256 a, uint256 b) public {
        a = bound(a, MAX_PPM + 1, type(uint256).max);
        b = bound(b, MAX_PPM + 1, type(uint256).max);
        bytes memory expectedError = abi.encodeWithSelector(PPMMath.PPMMathInvalidMulPPM.selector, a, b);
        vm.expectRevert(expectedError);
        PPMMath.mulPPM(a, b);
    }

    function test_mullPPMRoundUp_RevertWhen_InvalidPPM(uint256 a, uint256 b) public {
        b = bound(b, MAX_PPM + 1, type(uint256).max);
        bytes memory expectedError = abi.encodeWithSelector(PPMMath.PPMMathInvalidPPM.selector, b);
        vm.expectRevert(expectedError);
        PPMMath.mulPPMRoundUp(a, b);
    }
}
