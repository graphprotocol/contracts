// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "forge-std/console.sol";

/**
 * @title BaseTest
 * @notice Base contract for all forge tests
 */
abstract contract BaseTest is Test {
    // Common addresses
    address internal constant ZERO_ADDRESS = address(0);

    // Common constants
    uint256 internal constant PPM = 1_000_000; // Parts per million (100%)
    uint256 internal constant DEFAULT_ISSUANCE_PER_BLOCK = 120.73 ether; // 120.73 GRT per block

    // Test accounts
    address internal governor;
    address internal nonGovernor;
    address internal operator;
    address internal user;
    address internal indexer1;
    address internal indexer2;
    address internal selfMintingTarget;

    /**
     * @notice Set up test accounts
     */
    function setUp() public virtual {
        // Create test accounts with labels
        governor = makeAddr("governor");
        nonGovernor = makeAddr("nonGovernor");
        operator = makeAddr("operator");
        user = makeAddr("user");
        indexer1 = makeAddr("indexer1");
        indexer2 = makeAddr("indexer2");
        selfMintingTarget = makeAddr("selfMintingTarget");

        // Fund accounts with ETH
        vm.deal(governor, 100 ether);
        vm.deal(nonGovernor, 100 ether);
        vm.deal(operator, 100 ether);
        vm.deal(user, 100 ether);
        vm.deal(indexer1, 100 ether);
        vm.deal(indexer2, 100 ether);
        vm.deal(selfMintingTarget, 100 ether);
    }
}
