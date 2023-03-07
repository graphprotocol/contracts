// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.13;

import { SD59x18, wrap, unwrap, convert, exp, mul, div, sub } from "@prb/math/src/SD59x18.sol";
import "hardhat/console.sol";

// *** PRB-Math ***
// - exp(x) with -41.446531673892822322 <= x <= 133.084258667509499441
// - where x is λ * STAKE / FEES
// - For any x less than -41.446531673892822322, the result is zero.

contract TestPRB {
    // INPUTS
    uint256 constant FEES = 10e18;
    uint256 constant STAKE = 100e18;
    uint32 constant LAMBDA_NUMERATOR = 20;
    uint32 constant LAMBDA_DENOMINATOR = 10;
    SD59x18 constant ONE = SD59x18.wrap(1e18);

    function PRBCalcTx() public returns (int256) {
        return PRBCalc();
    }

    function PRBCalc() public view returns (int256) {
        SD59x18 exponent = div(
            mul(convert(-int32(LAMBDA_NUMERATOR)), convert(int256(STAKE))),
            mul(convert(int32(LAMBDA_DENOMINATOR)), convert(int256(FEES)))
        );
        SD59x18 exponential = exp(exponent);
        SD59x18 factor = sub(ONE, exponential);

        return convert(mul(factor, convert(int256(FEES))));
    }

    function PRBExpTx(int256 x) public returns (SD59x18) {
        return PRBExp(x);
    }

    function PRBExp(int256 x) public view returns (SD59x18) {
        return exp(convert(x));
    }

    function PRBExpMul(int256 x) public view returns (int256) {
        return convert(mul(PRBExp(x), wrap(1e36)));
    }
}
