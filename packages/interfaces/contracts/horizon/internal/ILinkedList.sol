// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

/**
 * @title Interface for the {LinkedList} library contract.
 * @author Edge & Node
 * @notice Interface for managing linked list data structures
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface ILinkedList {
    /**
     * @notice Represents a linked list
     * @param head The head of the list
     * @param tail The tail of the list
     * @param nonce A nonce, which can optionally be used to generate unique ids
     * @param count The number of items in the list
     */
    struct List {
        bytes32 head;
        bytes32 tail;
        uint256 nonce;
        uint256 count;
    }

    /**
     * @notice Thrown when trying to remove an item from an empty list
     */
    error LinkedListEmptyList();

    /**
     * @notice Thrown when trying to add an item to a list that has reached the maximum number of elements
     */
    error LinkedListMaxElementsExceeded();

    /**
     * @notice Thrown when trying to traverse a list with more iterations than elements
     */
    error LinkedListInvalidIterations();

    /**
     * @notice Thrown when trying to add an item with id equal to bytes32(0)
     */
    error LinkedListInvalidZeroId();
}
