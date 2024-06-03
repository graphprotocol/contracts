/*

  Copyright 2017 Bprotocol Foundation, 2019 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/

// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.26;

// solhint-disable indent
/// @dev Signed, fixed-point, 127-bit precision math library.
library LibFixedMath {
    // 1
    int256 private constant FIXED_1 = int256(0x0000000000000000000000000000000080000000000000000000000000000000);
    // 2**255
    int256 private constant MIN_FIXED_VAL = type(int256).min;
    // 0
    int256 private constant EXP_MAX_VAL = 0;
    // -63.875
    int256 private constant EXP_MIN_VAL = -int256(0x0000000000000000000000000000001ff0000000000000000000000000000000);

    /// @dev Get one as a fixed-point number.
    function one() internal pure returns (int256 f) {
        f = FIXED_1;
    }

    /// @dev Returns the addition of two fixed point numbers, reverting on overflow.
    function sub(int256 a, int256 b) internal pure returns (int256 c) {
        if (b == MIN_FIXED_VAL) {
            revert("out-of-bounds");
        }
        c = _add(a, -b);
    }

    /// @dev Returns the multiplication of two fixed point numbers, reverting on overflow.
    function mul(int256 a, int256 b) internal pure returns (int256 c) {
        c = _mul(a, b) / FIXED_1;
    }

    /// @dev Performs (a * n) / d, without scaling for precision.
    function mulDiv(int256 a, int256 n, int256 d) internal pure returns (int256 c) {
        c = _div(_mul(a, n), d);
    }

    /// @dev Returns the unsigned integer result of multiplying a fixed-point
    ///      number with an integer, reverting if the multiplication overflows.
    ///      Negative results are clamped to zero.
    function uintMul(int256 f, uint256 u) internal pure returns (uint256) {
        if (int256(u) < int256(0)) {
            revert("out-of-bounds");
        }
        int256 c = _mul(f, int256(u));
        if (c <= 0) {
            return 0;
        }
        return uint256(uint256(c) >> 127);
    }

    /// @dev Convert signed `n` / `d` to a fixed-point number.
    function toFixed(int256 n, int256 d) internal pure returns (int256 f) {
        f = _div(_mul(n, FIXED_1), d);
    }

    /// @dev Convert a fixed-point number to an integer.
    function toInteger(int256 f) internal pure returns (int256 n) {
        return f / FIXED_1;
    }

    /// @dev Compute the natural exponent for a fixed-point number EXP_MIN_VAL <= `x` <= 1
    function exp(int256 x) internal pure returns (int256 r) {
        if (x < EXP_MIN_VAL) {
            // Saturate to zero below EXP_MIN_VAL.
            return 0;
        }
        if (x == 0) {
            return FIXED_1;
        }
        if (x > EXP_MAX_VAL) {
            revert("out-of-bounds");
        }

        // Rewrite the input as a product of natural exponents and a
        // single residual q, where q is a number of small magnitude.
        // For example: e^-34.419 = e^(-32 - 2 - 0.25 - 0.125 - 0.044)
        //              = e^-32 * e^-2 * e^-0.25 * e^-0.125 * e^-0.044
        //              -> q = -0.044

        // Multiply with the taylor series for e^q
        int256 y;
        int256 z;
        // q = x % 0.125 (the residual)
        z = y = x % 0x0000000000000000000000000000000010000000000000000000000000000000;
        z = (z * y) / FIXED_1;
        r += z * 0x10e1b3be415a0000; // add y^02 * (20! / 02!)
        z = (z * y) / FIXED_1;
        r += z * 0x05a0913f6b1e0000; // add y^03 * (20! / 03!)
        z = (z * y) / FIXED_1;
        r += z * 0x0168244fdac78000; // add y^04 * (20! / 04!)
        z = (z * y) / FIXED_1;
        r += z * 0x004807432bc18000; // add y^05 * (20! / 05!)
        z = (z * y) / FIXED_1;
        r += z * 0x000c0135dca04000; // add y^06 * (20! / 06!)
        z = (z * y) / FIXED_1;
        r += z * 0x0001b707b1cdc000; // add y^07 * (20! / 07!)
        z = (z * y) / FIXED_1;
        r += z * 0x000036e0f639b800; // add y^08 * (20! / 08!)
        z = (z * y) / FIXED_1;
        r += z * 0x00000618fee9f800; // add y^09 * (20! / 09!)
        z = (z * y) / FIXED_1;
        r += z * 0x0000009c197dcc00; // add y^10 * (20! / 10!)
        z = (z * y) / FIXED_1;
        r += z * 0x0000000e30dce400; // add y^11 * (20! / 11!)
        z = (z * y) / FIXED_1;
        r += z * 0x000000012ebd1300; // add y^12 * (20! / 12!)
        z = (z * y) / FIXED_1;
        r += z * 0x0000000017499f00; // add y^13 * (20! / 13!)
        z = (z * y) / FIXED_1;
        r += z * 0x0000000001a9d480; // add y^14 * (20! / 14!)
        z = (z * y) / FIXED_1;
        r += z * 0x00000000001c6380; // add y^15 * (20! / 15!)
        z = (z * y) / FIXED_1;
        r += z * 0x000000000001c638; // add y^16 * (20! / 16!)
        z = (z * y) / FIXED_1;
        r += z * 0x0000000000001ab8; // add y^17 * (20! / 17!)
        z = (z * y) / FIXED_1;
        r += z * 0x000000000000017c; // add y^18 * (20! / 18!)
        z = (z * y) / FIXED_1;
        r += z * 0x0000000000000014; // add y^19 * (20! / 19!)
        z = (z * y) / FIXED_1;
        r += z * 0x0000000000000001; // add y^20 * (20! / 20!)
        r = r / 0x21c3677c82b40000 + y + FIXED_1; // divide by 20! and then add y^1 / 1! + y^0 / 0!

        // Multiply with the non-residual terms.
        x = -x;
        // e ^ -32
        if ((x & int256(0x0000000000000000000000000000001000000000000000000000000000000000)) != 0) {
            r =
                (r * int256(0x00000000000000000000000000000000000000f1aaddd7742e56d32fb9f99744)) /
                int256(0x0000000000000000000000000043cbaf42a000812488fc5c220ad7b97bf6e99e); // * e ^ -32
        }
        // e ^ -16
        if ((x & int256(0x0000000000000000000000000000000800000000000000000000000000000000)) != 0) {
            r =
                (r * int256(0x00000000000000000000000000000000000afe10820813d65dfe6a33c07f738f)) /
                int256(0x000000000000000000000000000005d27a9f51c31b7c2f8038212a0574779991); // * e ^ -16
        }
        // e ^ -8
        if ((x & int256(0x0000000000000000000000000000000400000000000000000000000000000000)) != 0) {
            r =
                (r * int256(0x0000000000000000000000000000000002582ab704279e8efd15e0265855c47a)) /
                int256(0x0000000000000000000000000000001b4c902e273a58678d6d3bfdb93db96d02); // * e ^ -8
        }
        // e ^ -4
        if ((x & int256(0x0000000000000000000000000000000200000000000000000000000000000000)) != 0) {
            r =
                (r * int256(0x000000000000000000000000000000001152aaa3bf81cb9fdb76eae12d029571)) /
                int256(0x00000000000000000000000000000003b1cc971a9bb5b9867477440d6d157750); // * e ^ -4
        }
        // e ^ -2
        if ((x & int256(0x0000000000000000000000000000000100000000000000000000000000000000)) != 0) {
            r =
                (r * int256(0x000000000000000000000000000000002f16ac6c59de6f8d5d6f63c1482a7c86)) /
                int256(0x000000000000000000000000000000015bf0a8b1457695355fb8ac404e7a79e3); // * e ^ -2
        }
        // e ^ -1
        if ((x & int256(0x0000000000000000000000000000000080000000000000000000000000000000)) != 0) {
            r =
                (r * int256(0x000000000000000000000000000000004da2cbf1be5827f9eb3ad1aa9866ebb3)) /
                int256(0x00000000000000000000000000000000d3094c70f034de4b96ff7d5b6f99fcd8); // * e ^ -1
        }
        // e ^ -0.5
        if ((x & int256(0x0000000000000000000000000000000040000000000000000000000000000000)) != 0) {
            r =
                (r * int256(0x0000000000000000000000000000000063afbe7ab2082ba1a0ae5e4eb1b479dc)) /
                int256(0x00000000000000000000000000000000a45af1e1f40c333b3de1db4dd55f29a7); // * e ^ -0.5
        }
        // e ^ -0.25
        if ((x & int256(0x0000000000000000000000000000000020000000000000000000000000000000)) != 0) {
            r =
                (r * int256(0x0000000000000000000000000000000070f5a893b608861e1f58934f97aea57d)) /
                int256(0x00000000000000000000000000000000910b022db7ae67ce76b441c27035c6a1); // * e ^ -0.25
        }
        // e ^ -0.125
        if ((x & int256(0x0000000000000000000000000000000010000000000000000000000000000000)) != 0) {
            r =
                (r * int256(0x00000000000000000000000000000000783eafef1c0a8f3978c7f81824d62ebf)) /
                int256(0x0000000000000000000000000000000088415abbe9a76bead8d00cf112e4d4a8); // * e ^ -0.125
        }
    }

    /// @dev Returns the multiplication two numbers, reverting on overflow.
    function _mul(int256 a, int256 b) private pure returns (int256 c) {
        if (a == 0 || b == 0) {
            return 0;
        }
        unchecked {
            c = a * b;
            if (c / a != b || c / b != a) {
                revert("overflow");
            }
        }
    }

    /// @dev Returns the division of two numbers, reverting on division by zero.
    function _div(int256 a, int256 b) private pure returns (int256 c) {
        if (b == 0) {
            revert("overflow");
        }
        if (a == MIN_FIXED_VAL && b == -1) {
            revert("overflow");
        }
        unchecked {
            c = a / b;
        }
    }

    /// @dev Adds two numbers, reverting on overflow.
    function _add(int256 a, int256 b) private pure returns (int256 c) {
        unchecked {
            c = a + b;
            if ((a < 0 && b < 0 && c > a) || (a > 0 && b > 0 && c < a)) {
                revert("overflow");
            }
        }
    }
}
