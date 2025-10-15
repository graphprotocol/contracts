// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-increment-by-one, gas-strict-inequalities

import { ILinkedList } from "@graphprotocol/interfaces/contracts/horizon/internal/ILinkedList.sol";

/**
 * @title LinkedList library
 * @author Edge & Node
 * @notice A library to manage singly linked lists.
 *
 * The library makes no assumptions about the contents of the items, the only
 * requirements on the items are:
 * - they must be represented by a unique bytes32 id
 * - the id of the item must not be bytes32(0)
 * - each item must have a reference to the next item in the list
 * - the list cannot have more than `MAX_ITEMS` items
 *
 * A contract using this library must store:
 * - a LinkedList.List to keep track of the list metadata
 * - a mapping from bytes32 to the item data
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
library LinkedList {
    using LinkedList for ILinkedList.List;

    /// @notice Empty bytes constant
    bytes internal constant NULL_BYTES = bytes("");

    /// @notice Maximum amount of items allowed in the list
    uint256 internal constant MAX_ITEMS = 10_000;

    /**
     * @notice Adds an item to the list.
     * The item is added to the end of the list.
     * @dev Note that this function will not take care of linking the
     * old tail to the new item. The caller should take care of this.
     * It will also not ensure id uniqueness.
     * @dev There is a maximum number of elements that can be added to the list.
     * @param self The list metadata
     * @param id The id of the item to add
     */
    function addTail(ILinkedList.List storage self, bytes32 id) internal {
        require(self.count < MAX_ITEMS, ILinkedList.LinkedListMaxElementsExceeded());
        require(id != bytes32(0), ILinkedList.LinkedListInvalidZeroId());
        self.tail = id;
        self.nonce += 1;
        if (self.count == 0) self.head = id;
        self.count += 1;
    }

    /**
     * @notice Removes an item from the list.
     * The item is removed from the beginning of the list.
     * @param self The list metadata
     * @param getNextItem A function to get the next item in the list. It should take
     * the id of the current item and return the id of the next item.
     * @param deleteItem A function to delete an item. This should delete the item from
     * the contract storage. It takes the id of the item to delete.
     * @return The id of the head of the list.
     */
    function removeHead(
        ILinkedList.List storage self,
        function(bytes32) view returns (bytes32) getNextItem,
        function(bytes32) deleteItem
    ) internal returns (bytes32) {
        require(self.count > 0, ILinkedList.LinkedListEmptyList());
        bytes32 nextItem = getNextItem(self.head);
        deleteItem(self.head);
        self.count -= 1;
        self.head = nextItem;
        if (self.count == 0) self.tail = bytes32(0);
        return self.head;
    }

    /**
     * @notice Traverses the list and processes each item.
     * It deletes the processed items from both the list and the storage mapping.
     * @param self The list metadata
     * @param getNextItem A function to get the next item in the list. It should take
     * the id of the current item and return the id of the next item.
     * @param processItem A function to process an item. The function should take the id of the item
     * and an accumulator, and return:
     * - a boolean indicating whether the traversal should stop
     * - an accumulator to pass data between iterations
     * @param deleteItem A function to delete an item. This should delete the item from
     * the contract storage. It takes the id of the item to delete.
     * @param processInitAcc The initial accumulator data
     * @param iterations The maximum number of iterations to perform. If 0, the traversal will continue
     * until the end of the list.
     * @return The number of items processed
     * @return The final accumulator data.
     */
    function traverse(
        ILinkedList.List storage self,
        function(bytes32) view returns (bytes32) getNextItem,
        function(bytes32, bytes memory) returns (bool, bytes memory) processItem,
        function(bytes32) deleteItem,
        bytes memory processInitAcc,
        uint256 iterations
    ) internal returns (uint256, bytes memory) {
        require(iterations <= self.count, ILinkedList.LinkedListInvalidIterations());

        uint256 itemCount = 0;
        iterations = (iterations == 0) ? self.count : iterations;

        bytes32 cursor = self.head;

        while (cursor != bytes32(0) && iterations > 0) {
            (bool shouldBreak, bytes memory acc_) = processItem(cursor, processInitAcc);

            if (shouldBreak) break;

            processInitAcc = acc_;
            cursor = self.removeHead(getNextItem, deleteItem);

            iterations--;
            itemCount++;
        }

        return (itemCount, processInitAcc);
    }
}
