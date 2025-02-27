// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { LinkedList } from "../../../contracts/libraries/LinkedList.sol";

import { ListImplementation } from "./ListImplementation.sol";

contract LinkedListTest is Test, ListImplementation {
    using LinkedList for LinkedList.List;

    function setUp() internal {
        list = LinkedList.List({ head: bytes32(0), tail: bytes32(0), nonce: 0, count: 0 });
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_Add_RevertGiven_TheItemIdIsZero() external {
        vm.expectRevert(LinkedList.LinkedListInvalidZeroId.selector);
        list.addTail(bytes32(0));
    }

    function test_Add_GivenTheListIsEmpty() external {
        _assert_addItem(_buildItemId(list.nonce), 0);
    }

    function test_Add_GivenTheListIsNotEmpty() external {
        // init list
        _assert_addItem(_buildItemId(list.nonce), 0);

        // add to a non empty list
        _assert_addItem(_buildItemId(list.nonce), 1);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_Add_RevertGiven_TheListIsAtMaxSize() external {
        for (uint256 i = 0; i < LinkedList.MAX_ITEMS; i++) {
            bytes32 id = _buildItemId(list.nonce);
            _addItemToList(list, id, i);
        }

        vm.expectRevert(LinkedList.LinkedListMaxElementsExceeded.selector);
        list.addTail(_buildItemId(list.nonce));
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_Remove_RevertGiven_TheListIsEmpty() external {
        vm.expectRevert(LinkedList.LinkedListEmptyList.selector);
        list.removeHead(_getNextItem, _deleteItem);
    }

    function test_Remove_GivenTheListIsNotEmpty() external {
        _assert_addItem(_buildItemId(list.nonce), 0);
        _assert_removeItem();
    }

    function test_TraverseGivenTheListIsEmpty() external {
        _assert_traverseList(_processItemAddition, abi.encode(0), 0, abi.encode(0));
    }

    modifier givenTheListIsNotEmpty() {
        for (uint256 i = 0; i < LIST_LENGTH; i++) {
            bytes32 id = _buildItemId(list.nonce);
            _assert_addItem(id, i);
        }
        _;
    }

    function test_TraverseWhenIterationsAreNotSpecified() external givenTheListIsNotEmpty {
        // calculate sum of all item idexes - it's what _processItemAddition does
        uint256 sum = 0;
        for (uint256 i = 0; i < list.count; i++) {
            sum += i;
        }
        _assert_traverseList(_processItemAddition, abi.encode(0), 0, abi.encode(sum));
    }

    function test_TraverseWhenIterationsAreSpecified(uint256 n) external givenTheListIsNotEmpty {
        vm.assume(n > 0);
        vm.assume(n < LIST_LENGTH);
        uint256 sum = 0;
        for (uint256 i = 0; i < n; i++) {
            sum += i;
        }
        _assert_traverseList(_processItemAddition, abi.encode(0), n, abi.encode(sum));
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_TraverseWhenIterationsAreInvalid() external givenTheListIsNotEmpty {
        uint256 n = LIST_LENGTH + 1;
        uint256 sum = 0;
        for (uint256 i = 0; i < n; i++) {
            sum += i;
        }
        vm.expectRevert(LinkedList.LinkedListInvalidIterations.selector);
        _assert_traverseList(_processItemAddition, abi.encode(0), n, abi.encode(sum));
    }

    // -- Assertions --
    function _assert_addItem(bytes32 id, uint256 idIndex) internal {
        uint256 beforeNonce = list.nonce;
        uint256 beforeCount = list.count;
        bytes32 beforeHead = list.head;

        ids[idIndex] = _addItemToList(list, id, idIndex);

        uint256 afterNonce = list.nonce;
        uint256 afterCount = list.count;
        bytes32 afterTail = list.tail;
        bytes32 afterHead = list.head;

        assertEq(afterNonce, beforeNonce + 1);
        assertEq(afterCount, beforeCount + 1);

        if (beforeCount == 0) {
            assertEq(afterHead, id);
        } else {
            assertEq(afterHead, beforeHead);
        }
        assertEq(afterTail, id);
    }

    function _assert_removeItem() internal {
        uint256 beforeNonce = list.nonce;
        uint256 beforeCount = list.count;
        bytes32 beforeTail = list.tail;
        bytes32 beforeHead = list.head;

        Item memory beforeHeadItem = items[beforeHead];

        list.removeHead(_getNextItem, _deleteItem);

        uint256 afterNonce = list.nonce;
        uint256 afterCount = list.count;
        bytes32 afterTail = list.tail;
        bytes32 afterHead = list.head;

        assertEq(afterNonce, beforeNonce);
        assertEq(afterCount, beforeCount - 1);

        if (afterCount == 0) {
            assertEq(afterTail, bytes32(0));
        } else {
            assertEq(afterTail, beforeTail);
        }
        assertEq(afterHead, beforeHeadItem.next);
    }

    function _assert_traverseList(
        function(bytes32, bytes memory) internal returns (bool, bytes memory) _processItem,
        bytes memory _initAcc,
        uint256 _n,
        bytes memory _expectedAcc
    ) internal {
        uint256 beforeNonce = list.nonce;
        uint256 beforeCount = list.count;
        bytes32 beforeTail = list.tail;
        bytes32 beforeHead = list.head;

        // calculate after head item
        bytes32 calcAfterHead = beforeHead;
        if (_n != 0) {
            for (uint256 i = 0; i < _n; i++) {
                calcAfterHead = _getNextItem(calcAfterHead);
            }
        }

        (uint256 processedCount, bytes memory acc) = list.traverse(
            _getNextItem,
            _processItem,
            _deleteItem,
            _initAcc,
            _n
        );
        uint256 afterNonce = list.nonce;
        uint256 afterCount = list.count;
        bytes32 afterTail = list.tail;
        bytes32 afterHead = list.head;

        assertEq(processedCount, _n == 0 ? beforeCount : _n);
        assertEq(acc, _expectedAcc);

        assertEq(afterNonce, beforeNonce);
        assertEq(afterCount, _n == 0 ? 0 : beforeCount - _n);

        if (_n == 0) {
            assertEq(afterTail, bytes32(0));
            assertEq(afterHead, bytes32(0));
        } else {
            assertEq(afterTail, beforeTail);
            assertEq(afterHead, calcAfterHead);
        }
    }
}
