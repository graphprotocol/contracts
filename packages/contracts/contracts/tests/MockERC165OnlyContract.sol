// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.7.6;

import { ERC165 } from "@openzeppelin/contracts/introspection/ERC165.sol";

/**
 * @title MockERC165OnlyContract
 * @author Edge & Node
 * @notice A mock contract that supports ERC-165 but not IRewardsEligibilityOracle
 * @dev Used for testing ERC-165 interface checking in RewardsManager
 */
contract MockERC165OnlyContract is ERC165 {
    /**
     * @notice A dummy function to make this a non-trivial contract
     * @return A dummy string
     */
    function dummyFunction() external pure returns (string memory) {
        return "This contract only supports ERC-165";
    }
}
