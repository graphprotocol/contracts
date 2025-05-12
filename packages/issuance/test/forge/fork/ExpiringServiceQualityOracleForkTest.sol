// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.30;

import "../utils/ArbitrumForkTest.sol";
import "../../../contracts/quality/ExpiringServiceQualityOracle.sol";
import "../utils/mocks/MockGraphProxy.sol";

/**
 * @title ExpiringServiceQualityOracleForkTest
 * @notice Fork test for the ExpiringServiceQualityOracle contract on Arbitrum
 */
contract ExpiringServiceQualityOracleForkTest is ArbitrumForkTest {
    // Contracts
    ExpiringServiceQualityOracle public oracle;
    MockGraphProxy public oracleProxy;

    // Test parameters
    uint256 public constant VALIDITY_PERIOD = 7 days;

    function setUp() public override {
        super.setUp();

        // Fork Arbitrum at the latest block
        setUpArbitrumFork(0);

        // Deploy the ExpiringServiceQualityOracle
        deployExpiringServiceQualityOracle();
    }

    function testInitialization() public view {
        // Test that the oracle was deployed correctly
        assertTrue(address(oracle) != address(0), "Oracle not deployed");

        // Test that the governor was set correctly
        assertTrue(oracle.hasRole(keccak256("GOVERNOR_ROLE"), governor), "Governor role not set");

        // Test that the validity period was set correctly
        assertEq(oracle.getValidityPeriod(), VALIDITY_PERIOD, "Validity period not set correctly");
    }

    function testGrantOracleRole() public {
        // Grant operator role to an operator
        vm.startPrank(governor);
        oracle.grantOperatorRole(operator);
        vm.stopPrank();

        // Operator grants oracle role
        vm.startPrank(operator);
        oracle.grantOracleRole(user);
        vm.stopPrank();

        // Test that the oracle role was granted correctly
        assertTrue(oracle.hasRole(keccak256("ORACLE_ROLE"), user), "Oracle role not granted");
    }

    function testAllowIndexer() public {
        // Grant operator role to an operator
        vm.startPrank(governor);
        oracle.grantOperatorRole(operator);
        vm.stopPrank();

        // Operator grants oracle role
        vm.startPrank(operator);
        oracle.grantOracleRole(operator);
        vm.stopPrank();

        // Allow an indexer
        vm.startPrank(operator);
        oracle.allowIndexer(indexer1, "");
        vm.stopPrank();

        // Test that the indexer was allowed correctly
        assertTrue(oracle.meetsRequirements(indexer1), "Indexer should meet requirements");

        // Test that the indexer's validation timestamp was set
        assertTrue(oracle.getLastValidationTime(indexer1) > 0, "Indexer validation timestamp not set");
    }

    function testIndexerRequirementsExpiration() public {
        // Grant operator role to an operator
        vm.startPrank(governor);
        oracle.grantOperatorRole(operator);
        vm.stopPrank();

        // Operator grants oracle role
        vm.startPrank(operator);
        oracle.grantOracleRole(operator);
        vm.stopPrank();

        // Allow an indexer
        vm.startPrank(operator);
        oracle.allowIndexer(indexer1, "");
        vm.stopPrank();

        // Test that the indexer meets requirements initially
        assertTrue(oracle.meetsRequirements(indexer1), "Indexer should meet requirements initially");

        // Advance time by less than the validity period
        vm.warp(block.timestamp + VALIDITY_PERIOD - 1 hours);

        // Test that the indexer still meets requirements
        assertTrue(oracle.meetsRequirements(indexer1), "Indexer should still meet requirements before expiration");

        // Advance time past the validity period
        vm.warp(block.timestamp + 2 hours);

        // Test that the indexer no longer meets requirements
        assertFalse(oracle.meetsRequirements(indexer1), "Indexer should not meet requirements after expiration");
    }

    function testUpdateValidityPeriod() public {
        // Update the validity period
        uint256 newValidityPeriod = 14 days;

        vm.startPrank(governor);
        oracle.setValidityPeriod(newValidityPeriod);
        vm.stopPrank();

        // Test that the validity period was updated correctly
        assertEq(oracle.getValidityPeriod(), newValidityPeriod, "Validity period not updated correctly");
    }

    function testSetZeroValidityPeriod() public {
        // Update the validity period to zero
        vm.startPrank(governor);
        oracle.setValidityPeriod(0);
        vm.stopPrank();

        // Test that the validity period was updated to zero
        assertEq(oracle.getValidityPeriod(), 0, "Validity period should be zero");
    }

    function testAllowMultipleIndexers() public {
        // Grant operator role to an operator
        vm.startPrank(governor);
        oracle.grantOperatorRole(operator);
        vm.stopPrank();

        // Operator grants oracle role
        vm.startPrank(operator);
        oracle.grantOracleRole(operator);
        vm.stopPrank();

        // Create an array of indexers
        address[] memory indexers = new address[](2);
        indexers[0] = indexer1;
        indexers[1] = indexer2;

        // Allow multiple indexers
        vm.startPrank(operator);
        oracle.allowIndexers(indexers, "");
        vm.stopPrank();

        // Test that both indexers were allowed correctly
        assertTrue(oracle.meetsRequirements(indexer1), "Indexer1 should meet requirements");
        assertTrue(oracle.meetsRequirements(indexer2), "Indexer2 should meet requirements");
    }

    // Helper function to deploy the ExpiringServiceQualityOracle
    function deployExpiringServiceQualityOracle() internal {
        // Deploy implementation
        ExpiringServiceQualityOracle oracleImpl = new ExpiringServiceQualityOracle(graphTokenAddress);

        // Create initialization data for the base contract
        bytes memory oracleInitData = abi.encodeWithSelector(
            bytes4(keccak256("initialize(address)")),
            governor
        );

        // Deploy proxy
        oracleProxy = new MockGraphProxy(address(oracleImpl), governor, oracleInitData);

        // Set up contract interface
        oracle = ExpiringServiceQualityOracle(address(oracleProxy));

        // Set the validity period after initialization
        vm.startPrank(governor);
        oracle.grantOperatorRole(governor);
        oracle.setValidityPeriod(VALIDITY_PERIOD);
        vm.stopPrank();
    }
}
