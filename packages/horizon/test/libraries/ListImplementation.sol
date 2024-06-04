// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { LinkedList } from "../../contracts/libraries/LinkedList.sol";

contract ListImplementation {
    using LinkedList for LinkedList.List;

    uint256 constant LIST_LENGTH = 100;

    struct Item {
        uint256 data;
        bytes32 next;
    }

    LinkedList.List public list;
    mapping(bytes32 id => Item data) public items;
    bytes32[LIST_LENGTH] public ids;

    function _addItemToList(LinkedList.List storage _list, bytes32 _id, uint256 _data) internal returns (bytes32) {
        items[_id] = Item({ data: _data, next: bytes32(0) });
        if (_list.count != 0) {
            items[_list.tail].next = _id;
        }
        _list.add(_id);
        return _id;
    }

    function _deleteItem(bytes32 _id) internal {
        delete items[_id];
    }

    function _getNextItem(bytes32 _id) internal view returns (bytes32) {
        return items[_id].next;
    }

    function _processItemAddition(bytes32 _id, bytes memory _acc) internal returns (bool, bytes memory) {
        uint256 sum = abi.decode(_acc, (uint256));
        sum += items[_id].data;
        return (false, abi.encode(sum)); // dont break, do delete
    }

    function _buildItemId(uint256 nonce) internal view returns (bytes32) {
        // use block.number to salt the id generation to avoid
        // accidentally using dirty state on repeat tests
        return bytes32(keccak256(abi.encode(nonce, block.number)));
    }
}
