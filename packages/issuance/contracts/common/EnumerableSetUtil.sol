// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.27;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title EnumerableSetUtil
 * @author Edge & Node
 * @notice Pagination helpers for OpenZeppelin EnumerableSet types.
 */
library EnumerableSetUtil {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /**
     * @notice Return a page of addresses from an AddressSet.
     * @param set The enumerable address set to paginate
     * @param offset Number of entries to skip
     * @param count Maximum number of entries to return
     * @return result Array of addresses (may be shorter than count)
     */
    function getPage(
        EnumerableSet.AddressSet storage set,
        uint256 offset,
        uint256 count
    ) internal view returns (address[] memory result) {
        uint256 total = set.length();
        // solhint-disable-next-line gas-strict-inequalities
        if (total <= offset) return new address[](0);

        uint256 remaining = total - offset;
        if (remaining < count) count = remaining;

        result = new address[](count);
        for (uint256 i = 0; i < count; ++i) result[i] = set.at(offset + i);
    }

    /**
     * @notice Return a page of bytes16 ids from a Bytes32Set (truncating each entry).
     * @param set The enumerable bytes32 set to paginate
     * @param offset Number of entries to skip
     * @param count Maximum number of entries to return
     * @return result Array of bytes16 values (may be shorter than count)
     */
    function getPageBytes16(
        EnumerableSet.Bytes32Set storage set,
        uint256 offset,
        uint256 count
    ) internal view returns (bytes16[] memory result) {
        uint256 total = set.length();
        // solhint-disable-next-line gas-strict-inequalities
        if (total <= offset) return new bytes16[](0);

        uint256 remaining = total - offset;
        if (remaining < count) count = remaining;

        result = new bytes16[](count);
        for (uint256 i = 0; i < count; ++i) result[i] = bytes16(set.at(offset + i));
    }
}
