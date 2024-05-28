// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.26;

library LinkedList {
    using LinkedList for List;

    error LinkedListEmptyList();

    bytes internal constant NULL_BYTES = bytes("");
    struct List {
        bytes32 head;
        bytes32 tail;
        uint256 nonce;
        uint256 count;
    }

    function add(List storage self, bytes32 id) internal {
        self.tail = id;
        self.nonce += 1;
        if (self.count == 0) self.head = id;
        self.count += 1;
    }

    function remove(
        List storage self,
        function(bytes32) view returns (bytes32) getNextItem,
        function(bytes32) deleteItem
    ) internal returns (bytes32) {
        require(self.count > 0, LinkedListEmptyList());
        bytes32 nextItem = getNextItem(self.head);
        deleteItem(self.head);
        self.count -= 1;
        self.head = nextItem;
        if (self.count == 0) self.tail = bytes32(0);
        return self.head;
    }

    function traverse(
        List storage self,
        function(bytes32) view returns (bytes32) getNextItem,
        function(bytes32, bytes memory) returns (bool, bool, bytes memory) processItem,
        function(bytes32) deleteItem,
        bytes memory processInitAcc,
        uint256 iterations
    ) internal returns (uint256, bytes memory) {
        uint256 itemCount = 0;
        bool traverseAll = iterations == 0;
        bytes memory acc = processInitAcc;

        bytes32 cursor = self.head;

        while (cursor != bytes32(0) && (traverseAll || iterations > 0)) {
            (bool shouldBreak, bool shouldDelete, bytes memory acc_) = processItem(cursor, acc);

            if (shouldBreak) break;

            acc = acc_;

            if (shouldDelete) {
                cursor = self.remove(getNextItem, deleteItem);
            } else {
                cursor = getNextItem(cursor);
            }

            if (!traverseAll) iterations--;
            itemCount++;
        }

        return (itemCount, acc);
    }
}
