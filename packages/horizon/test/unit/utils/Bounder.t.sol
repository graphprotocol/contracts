// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";

contract Bounder is Test {
    uint256 constant SECP256K1_CURVE_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    function boundKeyAndAddr(uint256 _value) internal pure returns (uint256, address) {
        uint256 key = bound(_value, 1, SECP256K1_CURVE_ORDER - 1);
        return (key, vm.addr(key));
    }

    function boundAddrAndKey(uint256 _value) internal pure returns (uint256, address) {
        return boundKeyAndAddr(_value);
    }

    function boundAddr(uint256 _value) internal pure returns (address) {
        (, address addr) = boundKeyAndAddr(_value);
        return addr;
    }

    function boundKey(uint256 _value) internal pure returns (uint256) {
        (uint256 key, ) = boundKeyAndAddr(_value);
        return key;
    }

    function boundChainId(uint256 _value) internal pure returns (uint256) {
        return bound(_value, 1, (2 ^ 64) - 1);
    }

    function boundTimestampMin(uint256 _value, uint256 _min) internal pure returns (uint256) {
        return bound(_value, _min, type(uint256).max);
    }

    function boundSkipFloor(uint256 _value, uint256 _min) internal view returns (uint256) {
        return boundSkip(_value, _min, type(uint256).max);
    }

    function boundSkipCeil(uint256 _value, uint256 _max) internal view returns (uint256) {
        return boundSkip(_value, 0, _max);
    }

    function boundSkip(uint256 _value, uint256 _min, uint256 _max) internal view returns (uint256) {
        return bound(_value, orTillEndOfTime(_min), orTillEndOfTime(_max));
    }

    function orTillEndOfTime(uint256 _value) internal view returns (uint256) {
        uint256 tillEndOfTime = type(uint256).max - block.timestamp;
        return _value < tillEndOfTime ? _value : tillEndOfTime;
    }
}
