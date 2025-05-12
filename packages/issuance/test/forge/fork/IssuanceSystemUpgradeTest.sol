// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.30;

import "../utils/ArbitrumForkTest.sol";
import "../../../contracts/allocate/IssuanceAllocator.sol";
import "../../../contracts/allocate/DirectAllocation.sol";
import "../../../contracts/quality/ServiceQualityOracle.sol";
import "../../../contracts/quality/ExpiringServiceQualityOracle.sol";
import "@graphprotocol/contracts/contracts/upgrades/GraphProxy.sol";
import "@graphprotocol/contracts/contracts/upgrades/GraphProxyAdmin.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IssuanceSystemUpgradeTest
 * @notice Fork test for testing the issuance system upgrade process on Arbitrum
 */
contract IssuanceSystemUpgradeTest is ArbitrumForkTest {
    // Issuance system contracts
    IssuanceAllocator public issuanceAllocator;
    ServiceQualityOracle public serviceQualityOracle;
    ExpiringServiceQualityOracle public expiringServiceQualityOracle;
    DirectAllocation public innovationAllocation;
    DirectAllocation public pilotAllocation;

    // Proxy contracts
    GraphProxy public issuanceAllocatorProxy;
    GraphProxy public serviceQualityOracleProxy;
    GraphProxy public expiringServiceQualityOracleProxy;
    GraphProxy public innovationAllocationProxy;
    GraphProxy public pilotAllocationProxy;

    // Proxy admin
    GraphProxyAdmin public proxyAdmin;

    // Test parameters
    uint256 public constant VALIDITY_PERIOD = 7 days;
    uint256 public constant ISSUANCE_PER_BLOCK = 120.73 ether; // 120.73 GRT per block

    // Allocation percentages
    uint256 public constant REWARDS_MANAGER_ALLOCATION = 790_000; // 79%
    uint256 public constant INNOVATION_ALLOCATION = 200_000;      // 20%
    uint256 public constant PILOT_ALLOCATION = 10_000;            // 1%

    /**
     * @notice Get the address of the GraphProxyAdmin from the address book
     * @return The address of the GraphProxyAdmin
     */
    function getProxyAdminAddress() internal view returns (address) {
        // On Arbitrum, the GraphProxyAdmin address is 0xF3B000a6749259539aF4E49f24EEc74Ea0e71430
        // This is hardcoded for simplicity, but in a real implementation, you would read it from the address book
        return 0xF3B000a6749259539aF4E49f24EEc74Ea0e71430;
    }

    // Events to test
    event IssuancePerBlockUpdated(uint256 oldIssuancePerBlock, uint256 newIssuancePerBlock);
    event AllocationTargetAdded(address indexed target, bool isSelfMinter);
    event TargetAllocationUpdated(address indexed target, uint256 newAllocation);
    event IssuanceDistributed(address indexed target, uint256 amount);

    function setUp() public override {
        super.setUp();

        // Fork Arbitrum at the latest block
        console.log("Setting up Arbitrum fork...");
        setUpArbitrumFork(0);
        console.log("Arbitrum fork setup successful");

        // Deploy the issuance system
        console.log("Deploying issuance system...");
        deployIssuanceSystem();
        console.log("Issuance system deployment successful");
    }

    // Helper function to deploy the issuance system
    function deployIssuanceSystem() internal {
        console.log("GraphToken address:", graphTokenAddress);

        // Get the existing GraphProxyAdmin
        proxyAdmin = GraphProxyAdmin(getProxyAdminAddress());
        console.log("Using existing GraphProxyAdmin at:", address(proxyAdmin));

        // Deploy IssuanceAllocator
        IssuanceAllocator issuanceAllocatorImpl = new IssuanceAllocator(graphTokenAddress);
        bytes memory issuanceAllocatorInitData = abi.encodeWithSelector(
            bytes4(keccak256("initialize(address)")),
            governor
        );
        issuanceAllocatorProxy = new GraphProxy(address(issuanceAllocatorImpl), address(proxyAdmin));

        // Accept the upgrade and initialize
        vm.startPrank(governor);
        proxyAdmin.acceptProxyAndCall(address(issuanceAllocatorImpl), address(issuanceAllocatorProxy), issuanceAllocatorInitData);
        vm.stopPrank();

        issuanceAllocator = IssuanceAllocator(address(issuanceAllocatorProxy));

        // Deploy ServiceQualityOracle
        ServiceQualityOracle serviceQualityOracleImpl = new ServiceQualityOracle(graphTokenAddress);
        bytes memory serviceQualityOracleInitData = abi.encodeWithSelector(
            bytes4(keccak256("initialize(address)")),
            governor
        );
        serviceQualityOracleProxy = new GraphProxy(address(serviceQualityOracleImpl), address(proxyAdmin));

        // Accept the upgrade and initialize
        vm.startPrank(governor);
        proxyAdmin.acceptProxyAndCall(address(serviceQualityOracleImpl), address(serviceQualityOracleProxy), serviceQualityOracleInitData);
        vm.stopPrank();

        serviceQualityOracle = ServiceQualityOracle(address(serviceQualityOracleProxy));

        // Deploy ExpiringServiceQualityOracle
        ExpiringServiceQualityOracle expiringServiceQualityOracleImpl = new ExpiringServiceQualityOracle(graphTokenAddress);
        bytes memory expiringServiceQualityOracleInitData = abi.encodeWithSelector(
            bytes4(keccak256("initialize(address)")),
            governor
        );
        expiringServiceQualityOracleProxy = new GraphProxy(address(expiringServiceQualityOracleImpl), address(proxyAdmin));

        // Accept the upgrade and initialize
        vm.startPrank(governor);
        proxyAdmin.acceptProxyAndCall(address(expiringServiceQualityOracleImpl), address(expiringServiceQualityOracleProxy), expiringServiceQualityOracleInitData);
        vm.stopPrank();

        expiringServiceQualityOracle = ExpiringServiceQualityOracle(address(expiringServiceQualityOracleProxy));

        // Set validity period for ExpiringServiceQualityOracle
        vm.startPrank(governor);
        expiringServiceQualityOracle.grantOperatorRole(governor);
        expiringServiceQualityOracle.setValidityPeriod(VALIDITY_PERIOD);
        vm.stopPrank();

        // Deploy DirectAllocation for Innovation
        DirectAllocation innovationAllocationImpl = new DirectAllocation(graphTokenAddress);
        bytes memory innovationAllocationInitData = abi.encodeWithSelector(
            bytes4(keccak256("initialize(address)")),
            governor
        );
        innovationAllocationProxy = new GraphProxy(address(innovationAllocationImpl), address(proxyAdmin));

        // Accept the upgrade and initialize
        vm.startPrank(governor);
        proxyAdmin.acceptProxyAndCall(address(innovationAllocationImpl), address(innovationAllocationProxy), innovationAllocationInitData);
        vm.stopPrank();

        innovationAllocation = DirectAllocation(address(innovationAllocationProxy));

        // Deploy DirectAllocation for Pilot
        DirectAllocation pilotAllocationImpl = new DirectAllocation(graphTokenAddress);
        bytes memory pilotAllocationInitData = abi.encodeWithSelector(
            bytes4(keccak256("initialize(address)")),
            governor
        );
        pilotAllocationProxy = new GraphProxy(address(pilotAllocationImpl), address(proxyAdmin));

        // Accept the upgrade and initialize
        vm.startPrank(governor);
        proxyAdmin.acceptProxyAndCall(address(pilotAllocationImpl), address(pilotAllocationProxy), pilotAllocationInitData);
        vm.stopPrank();

        pilotAllocation = DirectAllocation(address(pilotAllocationProxy));

        // Set issuance per block
        vm.startPrank(governor);
        issuanceAllocator.setIssuancePerBlock(ISSUANCE_PER_BLOCK);
        vm.stopPrank();
    }

    // Test the initial configuration of the issuance system
    function testInitialConfiguration() public {
        // Check IssuanceAllocator configuration
        assertEq(issuanceAllocator.issuancePerBlock(), ISSUANCE_PER_BLOCK, "Incorrect issuance per block");

        // Check ExpiringServiceQualityOracle configuration
        assertEq(expiringServiceQualityOracle.getValidityPeriod(), VALIDITY_PERIOD, "Incorrect validity period");

        // Check that the governor has the correct roles
        assertTrue(issuanceAllocator.hasRole(keccak256("GOVERNOR_ROLE"), governor), "Governor should have GOVERNOR_ROLE in IssuanceAllocator");
        assertTrue(serviceQualityOracle.hasRole(keccak256("GOVERNOR_ROLE"), governor), "Governor should have GOVERNOR_ROLE in ServiceQualityOracle");
        assertTrue(expiringServiceQualityOracle.hasRole(keccak256("GOVERNOR_ROLE"), governor), "Governor should have GOVERNOR_ROLE in ExpiringServiceQualityOracle");
        assertTrue(innovationAllocation.hasRole(keccak256("GOVERNOR_ROLE"), governor), "Governor should have GOVERNOR_ROLE in InnovationAllocation");
        assertTrue(pilotAllocation.hasRole(keccak256("GOVERNOR_ROLE"), governor), "Governor should have GOVERNOR_ROLE in PilotAllocation");
    }

    // Test adding allocation targets to the IssuanceAllocator
    function testAddAllocationTargets() public {
        vm.startPrank(governor);

        // Add RewardsManager as a self-minting target
        vm.expectEmit(true, true, true, true);
        emit AllocationTargetAdded(rewardsManagerAddress, true);
        issuanceAllocator.addAllocationTarget(rewardsManagerAddress, true);

        // Add Innovation Allocation as a non-self-minting target
        vm.expectEmit(true, true, true, true);
        emit AllocationTargetAdded(address(innovationAllocation), false);
        issuanceAllocator.addAllocationTarget(address(innovationAllocation), false);

        // Add Pilot Allocation as a non-self-minting target
        vm.expectEmit(true, true, true, true);
        emit AllocationTargetAdded(address(pilotAllocation), false);
        issuanceAllocator.addAllocationTarget(address(pilotAllocation), false);

        vm.stopPrank();

        // Verify targets were added correctly
        assertTrue(issuanceAllocator.isSelfMinter(rewardsManagerAddress), "RewardsManager should be a self-minter");
        assertFalse(issuanceAllocator.isSelfMinter(address(innovationAllocation)), "Innovation Allocation should not be a self-minter");
        assertFalse(issuanceAllocator.isSelfMinter(address(pilotAllocation)), "Pilot Allocation should not be a self-minter");

        // Verify allocations are initially zero
        assertEq(issuanceAllocator.getTargetAllocation(rewardsManagerAddress), 0, "Initial RewardsManager allocation should be zero");
        assertEq(issuanceAllocator.getTargetAllocation(address(innovationAllocation)), 0, "Initial Innovation allocation should be zero");
        assertEq(issuanceAllocator.getTargetAllocation(address(pilotAllocation)), 0, "Initial Pilot allocation should be zero");
    }

    // Test setting allocations in the IssuanceAllocator
    function testSetAllocations() public {
        // First add the targets
        vm.startPrank(governor);
        issuanceAllocator.addAllocationTarget(rewardsManagerAddress, true);
        issuanceAllocator.addAllocationTarget(address(innovationAllocation), false);
        issuanceAllocator.addAllocationTarget(address(pilotAllocation), false);

        // Set allocations
        vm.expectEmit(true, true, true, true);
        emit TargetAllocationUpdated(rewardsManagerAddress, REWARDS_MANAGER_ALLOCATION);
        issuanceAllocator.setTargetAllocation(rewardsManagerAddress, REWARDS_MANAGER_ALLOCATION);

        vm.expectEmit(true, true, true, true);
        emit TargetAllocationUpdated(address(innovationAllocation), INNOVATION_ALLOCATION);
        issuanceAllocator.setTargetAllocation(address(innovationAllocation), INNOVATION_ALLOCATION);

        vm.expectEmit(true, true, true, true);
        emit TargetAllocationUpdated(address(pilotAllocation), PILOT_ALLOCATION);
        issuanceAllocator.setTargetAllocation(address(pilotAllocation), PILOT_ALLOCATION);
        vm.stopPrank();

        // Verify allocations
        assertEq(issuanceAllocator.getTargetAllocation(rewardsManagerAddress), REWARDS_MANAGER_ALLOCATION, "Incorrect RewardsManager allocation");
        assertEq(issuanceAllocator.getTargetAllocation(address(innovationAllocation)), INNOVATION_ALLOCATION, "Incorrect Innovation allocation");
        assertEq(issuanceAllocator.getTargetAllocation(address(pilotAllocation)), PILOT_ALLOCATION, "Incorrect Pilot allocation");

        // Verify total allocation
        assertEq(issuanceAllocator.totalActiveAllocation(), REWARDS_MANAGER_ALLOCATION + INNOVATION_ALLOCATION + PILOT_ALLOCATION, "Incorrect total allocation");
    }

    // Test distributing issuance
    function testDistributeIssuance() public {
        // First add the targets and set allocations
        vm.startPrank(governor);
        issuanceAllocator.addAllocationTarget(rewardsManagerAddress, true);
        issuanceAllocator.addAllocationTarget(address(innovationAllocation), false);
        issuanceAllocator.addAllocationTarget(address(pilotAllocation), false);

        issuanceAllocator.setTargetAllocation(rewardsManagerAddress, REWARDS_MANAGER_ALLOCATION);
        issuanceAllocator.setTargetAllocation(address(innovationAllocation), INNOVATION_ALLOCATION);
        issuanceAllocator.setTargetAllocation(address(pilotAllocation), PILOT_ALLOCATION);
        vm.stopPrank();

        // Get initial balances
        uint256 innovationBalanceBefore = IERC20(graphTokenAddress).balanceOf(address(innovationAllocation));
        uint256 pilotBalanceBefore = IERC20(graphTokenAddress).balanceOf(address(pilotAllocation));

        // Mine some blocks to accumulate issuance
        vm.roll(block.number + 10);

        // Distribute issuance
        issuanceAllocator.distributeIssuance();

        // Get final balances
        uint256 innovationBalanceAfter = IERC20(graphTokenAddress).balanceOf(address(innovationAllocation));
        uint256 pilotBalanceAfter = IERC20(graphTokenAddress).balanceOf(address(pilotAllocation));

        // Verify balances increased for non-self-minting targets
        assertTrue(innovationBalanceAfter > innovationBalanceBefore, "Innovation allocation balance should increase");
        assertTrue(pilotBalanceAfter > pilotBalanceBefore, "Pilot allocation balance should increase");

        // Calculate expected issuance
        uint256 blocksPassed = 10;
        uint256 totalIssuance = ISSUANCE_PER_BLOCK * blocksPassed;
        uint256 expectedInnovationIssuance = (totalIssuance * INNOVATION_ALLOCATION) / PPM;
        uint256 expectedPilotIssuance = (totalIssuance * PILOT_ALLOCATION) / PPM;

        // Verify issuance amounts (with a small tolerance for rounding)
        assertApproxEqAbs(innovationBalanceAfter - innovationBalanceBefore, expectedInnovationIssuance, 1e9, "Incorrect Innovation issuance");
        assertApproxEqAbs(pilotBalanceAfter - pilotBalanceBefore, expectedPilotIssuance, 1e9, "Incorrect Pilot issuance");
    }

    // Test the ServiceQualityOracle
    function testServiceQualityOracle() public {
        address indexer = address(0x1234);

        // Grant oracle role
        vm.startPrank(governor);
        serviceQualityOracle.grantOperatorRole(governor);
        serviceQualityOracle.grantOracleRole(governor);
        vm.stopPrank();

        // Verify indexer is not allowed by default
        assertFalse(serviceQualityOracle.meetsRequirements(indexer), "Indexer should not meet requirements by default");

        // Allow indexer
        vm.startPrank(governor);
        serviceQualityOracle.allowIndexer(indexer, "");
        vm.stopPrank();

        // Verify indexer is now allowed
        assertTrue(serviceQualityOracle.meetsRequirements(indexer), "Indexer should meet requirements after being allowed");

        // Deny indexer
        vm.startPrank(governor);
        serviceQualityOracle.denyIndexer(indexer, "");
        vm.stopPrank();

        // Verify indexer is denied again
        assertFalse(serviceQualityOracle.meetsRequirements(indexer), "Indexer should not meet requirements after being denied");
    }

    // Test the ExpiringServiceQualityOracle
    function testExpiringServiceQualityOracle() public {
        address indexer = address(0x1234);

        // Grant oracle role
        vm.startPrank(governor);
        expiringServiceQualityOracle.grantOperatorRole(governor);
        expiringServiceQualityOracle.grantOracleRole(governor);
        vm.stopPrank();

        // Verify indexer is not allowed by default
        assertFalse(expiringServiceQualityOracle.meetsRequirements(indexer), "Indexer should not meet requirements by default");

        // Allow indexer
        vm.startPrank(governor);
        expiringServiceQualityOracle.allowIndexer(indexer, "");
        vm.stopPrank();

        // Verify indexer is now allowed
        assertTrue(expiringServiceQualityOracle.meetsRequirements(indexer), "Indexer should meet requirements after being allowed");

        // Fast forward past validity period
        vm.warp(block.timestamp + VALIDITY_PERIOD + 1);

        // Verify indexer is no longer allowed
        assertFalse(expiringServiceQualityOracle.meetsRequirements(indexer), "Indexer should not meet requirements after validity period");
    }
}
