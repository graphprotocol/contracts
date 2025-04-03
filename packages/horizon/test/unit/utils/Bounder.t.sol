// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";

contract Bounder is Test {
    uint256 constant SECP256K1_CURVE_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    function boundAddrAndKey(uint256 _value) internal pure returns (uint256, address) {
        uint256 signerKey = bound(_value, 1, SECP256K1_CURVE_ORDER - 1);
        return (signerKey, vm.addr(signerKey));
    }

    function boundAddr(uint256 _value) internal pure returns (address) {
        (, address addr) = boundAddrAndKey(_value);
        return addr;
    }

    function boundKey(uint256 _value) internal pure returns (uint256) {
        (uint256 key, ) = boundAddrAndKey(_value);
        return key;
    }

    function boundChainId(uint256 _value) internal pure returns (uint256) {
        return bound(_value, 1, (2 ^ 64) - 1);
    }

    function boundTimestampMin(uint256 _value, uint256 _min) internal pure returns (uint256) {
        return bound(_value, _min, type(uint256).max);
    }
}
