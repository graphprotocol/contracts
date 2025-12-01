// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title MockGraphTokenWithMinter
 * @notice Mock GraphToken for testing with isMinter method
 */
contract MockGraphTokenWithMinter {
    mapping(address => bool) public minter;

    function setMinter(address m, bool v) external {
        minter[m] = v;
    }

    function isMinter(address a) external view returns (bool) {
        return minter[a];
    }
}
