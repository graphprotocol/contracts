// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "./LibFixedMath.sol";

// *** LibFixedMath ***
// - exp(x) with -63.875 <= x <= 0
// - where x is λ * STAKE / FEES

contract TestLFM {
    // INPUTS
    uint256 constant ONEe18 = 1e18;
    uint256 constant FEES = 10e18;
    uint256 constant STAKE = 100e18;
    uint32 constant LAMBDA_NUMERATOR = 2;
    uint32 constant LAMBDA_DENOMINATOR = 10;
    uint32 constant ALPHA_NUMERATOR = 1;
    uint32 constant ALPHA_DENOMINATOR = 1;

    function LFMCalcTx() public returns (uint256) {
        return LFMCalc();
    }

    function LFMCalc() public view returns (uint256) {
        int256 exponent = LibFixedMath.div(
            LibFixedMath.mulDiv(LAMBDA_NUMERATOR, int256(STAKE), int256(FEES)),
            LAMBDA_DENOMINATOR
        );
        int256 exponential = LibFixedMath.exp(-exponent);
        int256 factor = LibFixedMath.sub(LibFixedMath.one(), exponential);

        return LibFixedMath.uintMul(factor, FEES);
    }

    function LFMCalcTx2() public returns (uint256) {
        return LFMCalc2();
    }

    function LFMCalc2() public view returns (uint256) {
        int256 alpha = LibFixedMath.toFixed(int32(ALPHA_NUMERATOR), int32(ALPHA_DENOMINATOR));
        int256 lambda = LibFixedMath.toFixed(int32(LAMBDA_NUMERATOR), int32(LAMBDA_DENOMINATOR));

        int256 exp = LibFixedMath.exp(-LibFixedMath.mulDiv(lambda, int256(STAKE), int256(FEES)));
        int256 factor = LibFixedMath.sub(LibFixedMath.one(), LibFixedMath.mul(alpha, exp));
        return LibFixedMath.uintMul(factor, FEES);
    }

    function LFMExpTx(uint256 x) public returns (int256) {
        return LFMExp(x);
    }

    function LFMExp(uint256 x) public view returns (int256) {
        return LibFixedMath.exp(-LibFixedMath.toFixed(x));
    }

    function LFMExpMul(uint256 x) public view returns (uint256) {
        return LibFixedMath.uintMul(LFMExp(x), ONEe18);
    }
}
