// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title MockERC165OnlyTarget
 * @author Edge & Node
 * @notice A mock contract that supports ERC-165 but not IIssuanceTarget
 * @dev Used for testing ERC-165 interface checking in IssuanceAllocator
 */
contract MockERC165OnlyTarget is ERC165 {
    /**
     * @notice A dummy function to make this a non-trivial contract
     * @return A string indicating this contract only supports ERC-165
     */
    function dummyFunction() external pure returns (string memory) {
        return "This contract only supports ERC-165";
    }
}
