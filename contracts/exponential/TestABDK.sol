// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.13;

import "./ABDKMath64x64.sol";
import "./ABDKMathQuad.sol";
import "hardhat/console.sol";

// *** ABDK ***

contract TestABDK {
    // INPUTS
    uint256 constant FEES = 10e18;
    uint256 constant STAKE = 100e18;
    bytes16 LAMBDA_NUMERATOR = ABDKMathQuad.fromUInt(2);
    bytes16 LAMBDA_DENOMINATOR = ABDKMathQuad.fromUInt(10);
    bytes16 ONE = ABDKMathQuad.fromUInt(1);

    function ABDKCalcTx() public returns (int256) {
        return ABDKCalc();
    }

    function ABDKCalc() public view returns (int256) {
        bytes16 fees = ABDKMathQuad.fromUInt(FEES);
        bytes16 stake = ABDKMathQuad.fromUInt(STAKE);
        bytes16 exponent = ABDKMathQuad.div(
            ABDKMathQuad.div(ABDKMathQuad.mul(LAMBDA_NUMERATOR, stake), LAMBDA_DENOMINATOR),
            fees
        );
        bytes16 exponential = ABDKMathQuad.exp(ABDKMathQuad.neg(exponent));
        bytes16 factor = ABDKMathQuad.sub(ONE, exponential);

        return ABDKMathQuad.toInt(ABDKMathQuad.mul(factor, fees));
    }

    function ABDKExpTx(bytes16 x) public returns (bytes16) {
        return ABDKExp(x);
    }

    function ABDKExp(bytes16 x) public view returns (bytes16) {
        return ABDKMathQuad.exp(x);
    }

    function ABDKExpMul(bytes16 x) public view returns (int256) {
        return ABDKMathQuad.toInt(ABDKMathQuad.mul(ABDKExp(x), ABDKMathQuad.fromInt(1e18)));
    }

    function fromInt(int256 x) public pure returns (bytes16) {
        return ABDKMathQuad.fromInt(x);
    }
}
