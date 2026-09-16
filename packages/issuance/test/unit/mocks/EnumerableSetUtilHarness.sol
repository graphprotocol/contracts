// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { EnumerableSetUtil } from "../../../contracts/common/EnumerableSetUtil.sol";

/// @notice Harness that exposes EnumerableSetUtil internal functions for testing.
contract EnumerableSetUtilHarness {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSetUtil for EnumerableSet.AddressSet;
    using EnumerableSetUtil for EnumerableSet.Bytes32Set;

    EnumerableSet.AddressSet private _addresses;
    EnumerableSet.Bytes32Set private _bytes32s;

    // -- AddressSet helpers --

    function addAddress(address a) external {
        _addresses.add(a);
    }

    function addressSetLength() external view returns (uint256) {
        return _addresses.length();
    }

    function getPage(uint256 offset, uint256 count) external view returns (address[] memory) {
        return _addresses.getPage(offset, count);
    }

    // -- Bytes32Set helpers --

    function addBytes32(bytes32 b) external {
        _bytes32s.add(b);
    }

    function bytes32SetLength() external view returns (uint256) {
        return _bytes32s.length();
    }

    function getPageBytes16(uint256 offset, uint256 count) external view returns (bytes16[] memory) {
        return _bytes32s.getPageBytes16(offset, count);
    }
}
