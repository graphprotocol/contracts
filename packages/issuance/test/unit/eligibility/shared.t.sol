// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { RewardsEligibilityOracle } from "../../../contracts/eligibility/RewardsEligibilityOracle.sol";
import { MockGraphToken } from "../mocks/MockGraphToken.sol";

/// @notice Shared test setup for RewardsEligibilityOracle tests.
contract RewardsEligibilityOracleSharedTest is Test {
    // -- Contracts --
    MockGraphToken internal token;
    RewardsEligibilityOracle internal oracle;

    // -- Accounts --
    address internal governor;
    address internal operator;
    address internal oracleAccount;
    address internal indexer1;
    address internal indexer2;
    address internal unauthorized;

    // -- Constants --
    bytes32 internal constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 internal constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 internal constant PAUSE_ROLE = keccak256("PAUSE_ROLE");

    uint256 internal constant DEFAULT_ELIGIBILITY_PERIOD = 14 days;
    uint256 internal constant DEFAULT_ORACLE_TIMEOUT = 7 days;

    function setUp() public virtual {
        // Use a realistic timestamp so eligibility period math works correctly
        vm.warp(1_700_000_000); // ~Nov 2023

        governor = makeAddr("governor");
        operator = makeAddr("operator");
        oracleAccount = makeAddr("oracle");
        indexer1 = makeAddr("indexer1");
        indexer2 = makeAddr("indexer2");
        unauthorized = makeAddr("unauthorized");

        // Deploy token
        token = new MockGraphToken();

        // Deploy RewardsEligibilityOracle behind proxy
        RewardsEligibilityOracle impl = new RewardsEligibilityOracle(address(token));
        bytes memory initData = abi.encodeCall(RewardsEligibilityOracle.initialize, (governor));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), address(this), initData);
        oracle = RewardsEligibilityOracle(address(proxy));

        // Label addresses
        vm.label(address(token), "GraphToken");
        vm.label(address(oracle), "RewardsEligibilityOracle");
    }

    // -- Helpers --

    /// @notice Grant operator role and then oracle role to oracleAccount
    function _setupOracleRole() internal {
        vm.prank(governor);
        oracle.grantRole(OPERATOR_ROLE, operator);
        vm.prank(operator);
        oracle.grantRole(ORACLE_ROLE, oracleAccount);
    }

    /// @notice Grant operator role to `operator`
    function _setupOperatorRole() internal {
        vm.prank(governor);
        oracle.grantRole(OPERATOR_ROLE, operator);
    }

    /// @notice Enable eligibility validation and set long oracle timeout to isolate eligibility checks.
    /// Also seeds lastOracleUpdateTime so the timeout condition doesn't bypass validation.
    function _enableValidation() internal {
        _setupOracleRole();
        vm.startPrank(operator);
        oracle.setEligibilityValidation(true);
        oracle.setOracleUpdateTimeout(365 days);
        vm.stopPrank();

        // Seed lastOracleUpdateTime by renewing a dummy address
        address dummy = makeAddr("dummy");
        _renewEligibility(dummy);
    }

    /// @notice Renew eligibility for a single indexer
    function _renewEligibility(address indexer) internal {
        address[] memory indexers = new address[](1);
        indexers[0] = indexer;
        vm.prank(oracleAccount);
        oracle.renewIndexerEligibility(indexers, "");
    }
}
