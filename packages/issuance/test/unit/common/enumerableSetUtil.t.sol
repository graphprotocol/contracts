// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";

import { EnumerableSetUtilHarness } from "../mocks/EnumerableSetUtilHarness.sol";

/// @notice Unit tests for EnumerableSetUtil pagination helpers.
contract EnumerableSetUtilTest is Test {
    /* solhint-disable graph/func-name-mixedcase */

    EnumerableSetUtilHarness internal harness;

    function setUp() public {
        harness = new EnumerableSetUtilHarness();
    }

    // ==================== getPage (AddressSet) ====================

    function test_GetPage_EmptySet_ReturnsEmpty() public view {
        address[] memory result = harness.getPage(0, 10);
        assertEq(result.length, 0);
    }

    function test_GetPage_ReturnsAllElements() public {
        address a1 = makeAddr("a1");
        address a2 = makeAddr("a2");
        address a3 = makeAddr("a3");
        harness.addAddress(a1);
        harness.addAddress(a2);
        harness.addAddress(a3);

        address[] memory result = harness.getPage(0, 10);
        assertEq(result.length, 3);
        assertEq(result[0], a1);
        assertEq(result[1], a2);
        assertEq(result[2], a3);
    }

    function test_GetPage_WithOffset() public {
        address a1 = makeAddr("a1");
        address a2 = makeAddr("a2");
        address a3 = makeAddr("a3");
        harness.addAddress(a1);
        harness.addAddress(a2);
        harness.addAddress(a3);

        address[] memory result = harness.getPage(1, 10);
        assertEq(result.length, 2);
        assertEq(result[0], a2);
        assertEq(result[1], a3);
    }

    function test_GetPage_WithCount() public {
        address a1 = makeAddr("a1");
        address a2 = makeAddr("a2");
        address a3 = makeAddr("a3");
        harness.addAddress(a1);
        harness.addAddress(a2);
        harness.addAddress(a3);

        address[] memory result = harness.getPage(0, 2);
        assertEq(result.length, 2);
        assertEq(result[0], a1);
        assertEq(result[1], a2);
    }

    function test_GetPage_OffsetAndCount() public {
        address a1 = makeAddr("a1");
        address a2 = makeAddr("a2");
        address a3 = makeAddr("a3");
        harness.addAddress(a1);
        harness.addAddress(a2);
        harness.addAddress(a3);

        address[] memory result = harness.getPage(1, 1);
        assertEq(result.length, 1);
        assertEq(result[0], a2);
    }

    function test_GetPage_OffsetAtEnd_ReturnsEmpty() public {
        harness.addAddress(makeAddr("a1"));

        address[] memory result = harness.getPage(1, 10);
        assertEq(result.length, 0);
    }

    function test_GetPage_OffsetPastEnd_ReturnsEmpty() public {
        harness.addAddress(makeAddr("a1"));

        address[] memory result = harness.getPage(5, 10);
        assertEq(result.length, 0);
    }

    function test_GetPage_CountClamped() public {
        address a1 = makeAddr("a1");
        harness.addAddress(a1);

        address[] memory result = harness.getPage(0, 100);
        assertEq(result.length, 1);
        assertEq(result[0], a1);
    }

    function test_GetPage_ZeroCount_ReturnsEmpty() public {
        harness.addAddress(makeAddr("a1"));

        address[] memory result = harness.getPage(0, 0);
        assertEq(result.length, 0);
    }

    // ==================== getPageBytes16 (Bytes32Set) ====================

    function test_GetPageBytes16_EmptySet_ReturnsEmpty() public view {
        bytes16[] memory result = harness.getPageBytes16(0, 10);
        assertEq(result.length, 0);
    }

    // forge-lint: disable(unsafe-typecast)
    function test_GetPageBytes16_ReturnsAllElements() public {
        bytes32 b1 = bytes32(bytes16(hex"00010002000300040005000600070008"));
        bytes32 b2 = bytes32(bytes16(hex"000a000b000c000d000e000f00100011"));
        harness.addBytes32(b1);
        harness.addBytes32(b2);

        bytes16[] memory result = harness.getPageBytes16(0, 10);
        assertEq(result.length, 2);
        assertEq(result[0], bytes16(b1));
        assertEq(result[1], bytes16(b2));
    }

    function test_GetPageBytes16_TruncatesBytes32ToBytes16() public {
        // The high 16 bytes should be kept, low 16 bytes discarded
        bytes32 full = hex"0102030405060708091011121314151617181920212223242526272829303132";
        harness.addBytes32(full);

        bytes16[] memory result = harness.getPageBytes16(0, 1);
        assertEq(result.length, 1);
        assertEq(result[0], bytes16(full));
    }

    function test_GetPageBytes16_WithOffset() public {
        bytes32 b1 = bytes32(bytes16(hex"aaaa0000000000000000000000000001"));
        bytes32 b2 = bytes32(bytes16(hex"bbbb0000000000000000000000000002"));
        bytes32 b3 = bytes32(bytes16(hex"cccc0000000000000000000000000003"));
        harness.addBytes32(b1);
        harness.addBytes32(b2);
        harness.addBytes32(b3);

        bytes16[] memory result = harness.getPageBytes16(1, 10);
        assertEq(result.length, 2);
        assertEq(result[0], bytes16(b2));
        assertEq(result[1], bytes16(b3));
    }

    function test_GetPageBytes16_WithCount() public {
        bytes32 b1 = bytes32(bytes16(hex"aaaa0000000000000000000000000001"));
        bytes32 b2 = bytes32(bytes16(hex"bbbb0000000000000000000000000002"));
        bytes32 b3 = bytes32(bytes16(hex"cccc0000000000000000000000000003"));
        harness.addBytes32(b1);
        harness.addBytes32(b2);
        harness.addBytes32(b3);

        bytes16[] memory result = harness.getPageBytes16(0, 2);
        assertEq(result.length, 2);
        assertEq(result[0], bytes16(b1));
        assertEq(result[1], bytes16(b2));
    }

    function test_GetPageBytes16_OffsetPastEnd_ReturnsEmpty() public {
        harness.addBytes32(bytes32(uint256(1)));

        bytes16[] memory result = harness.getPageBytes16(5, 10);
        assertEq(result.length, 0);
    }

    function test_GetPageBytes16_CountClamped() public {
        bytes32 b1 = bytes32(bytes16(hex"aaaa0000000000000000000000000001"));
        harness.addBytes32(b1);

        bytes16[] memory result = harness.getPageBytes16(0, 100);
        assertEq(result.length, 1);
        assertEq(result[0], bytes16(b1));
    }

    function test_GetPageBytes16_ZeroCount_ReturnsEmpty() public {
        harness.addBytes32(bytes32(uint256(1)));

        bytes16[] memory result = harness.getPageBytes16(0, 0);
        assertEq(result.length, 0);
    }

    // forge-lint: enable(unsafe-typecast)

    /* solhint-enable graph/func-name-mixedcase */
}
