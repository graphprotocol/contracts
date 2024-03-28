// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";

import "../contracts/disputes/DisputeManager.sol";

// Mocks

import "./mocks/MockGRTToken.sol";
import "./mocks/MockSubgraphService.sol";
import "./mocks/MockHorizonStaking.sol";

contract DisputeManagerTest is Test {
    DisputeManager disputeManager;

    address arbitrator = address(0x1);
    address serviceProvider = address(0x2);
    address fisherman = address(0x3);
    address allocationID = address(0x4);
    uint64 disputePeriod = 300; // 5 minutes
    uint256 minimumDeposit = 100 ether; // 100 GRT
    uint32 fishermanRewardPercentage = 100000; // 10%
    uint32 maxSlashingPercentage = 500000; // 50%
    MockGRTToken graphToken;
    MockSubgraphService subgraphService;
    MockHorizonStaking staking;

    // Setup

    function setUp() public {
        graphToken = new MockGRTToken();
        subgraphService = new MockSubgraphService(address(graphToken));
        staking = new MockHorizonStaking();

        disputeManager = new DisputeManager(
            subgraphService,
            staking,
            graphToken,
            arbitrator,
            disputePeriod,
            minimumDeposit,
            fishermanRewardPercentage,
            maxSlashingPercentage
        );
    }

    // Helper functions

    function createProvisionAndAllocte(address _allocationID) private {
        vm.startPrank(serviceProvider);
        graphToken.mint(serviceProvider, 10000 ether); // 10,000 GRT
        staking.provision(10000 ether, address(subgraphService), 500000, 0);
        bytes32 subgraphDeployment = keccak256(abi.encodePacked("Subgraph Deployment ID"));
        subgraphService.allocate(serviceProvider, subgraphDeployment, 10000 ether, _allocationID); // 10,000 GRT
        vm.stopPrank();
    }

    function createIndexingDispute(address _allocationID) private returns(bytes32 disputeID) {
        vm.startPrank(fisherman);
        graphToken.mint(fisherman, 200 ether); // 200 GRT
        graphToken.approve(address(disputeManager), 200 ether); // Allow DisputeManager to transfer 1000 GRT
        bytes32 _disputeID = disputeManager.createIndexingDispute(_allocationID, 200 ether); // Deposit 200 GRT
        vm.stopPrank();
        return _disputeID;
    }

    // Tests

    // Create dispute

    function testCreateIndexingDispute() public {
        createProvisionAndAllocte(allocationID);

        // fisherman actions
        bytes32 disputeID = createIndexingDispute(allocationID);
        assertTrue(disputeManager.isDisputeCreated(disputeID), "Dispute should be created.");
    }

    function test_RevertWhen_DisputeAlreadyCreated() public {
        createProvisionAndAllocte(allocationID);
        createIndexingDispute(allocationID);
        
        // Create another dispute with different fisherman
        address otherFisherman = address(0x5);
        vm.startPrank(otherFisherman);
        graphToken.mint(otherFisherman, 200 ether); // 200 GRT
        graphToken.approve(address(disputeManager), 200 ether); // Allow DisputeManager to transfer 1000 GRT
        vm.expectRevert("Dispute already created");
        disputeManager.createIndexingDispute(allocationID, 200 ether); // Deposit 200 GRT
        vm.stopPrank();
    }

    function test_RevertIf_DepositUnderMinimum() public {
        createProvisionAndAllocte(allocationID);

        // fisherman actions
        vm.startPrank(fisherman);
        graphToken.mint(fisherman, 50 ether);
        vm.expectRevert("Dispute deposit is under minimum required");
        disputeManager.createIndexingDispute(allocationID, 50 ether);
        vm.stopPrank();
    }

    function test_RevertIf_AllocationDoesNotExist() public {
        vm.startPrank(fisherman);
        graphToken.mint(fisherman, 100 ether);
        graphToken.approve(address(disputeManager), 100 ether);
        vm.expectRevert("Dispute allocation must exist");
        disputeManager.createIndexingDispute(allocationID, 100 ether);
        vm.stopPrank();
    }

    // Accept dispute

    function test_RevertIf_CallerIsNotArbitrator_AcceptDispute() public {
        // service provider actions
        createProvisionAndAllocte(allocationID);

        // fisherman actions
        bytes32 disputeID = createIndexingDispute(allocationID);

        // attempt to accept dispute as fisherman
        vm.prank(fisherman);
        vm.expectRevert("Caller is not the Arbitrator");
        disputeManager.acceptDispute(disputeID, 5000 ether);
    }

    function testAcceptDispute() public {
        createProvisionAndAllocte(allocationID);
        bytes32 disputeID = createIndexingDispute(allocationID);

        // arbitrator actions
        vm.prank(arbitrator);
        disputeManager.acceptDispute(disputeID, 5000 ether); // Slash service provider for 5000 GRT

        assertEq(graphToken.balanceOf(fisherman), 700 ether, "Fisherman should receive 50% of slashed tokens.");
        assertEq(graphToken.balanceOf(serviceProvider), 5000 ether, "Service provider should have 5000 GRT slashed.");
    }

    function test_RevertIf_SlashingOverMaxSlashPercentage() public {
        createProvisionAndAllocte(allocationID);
        bytes32 disputeID = createIndexingDispute(allocationID);

        // arbitrator actions
        vm.prank(arbitrator);
        vm.expectRevert("Slash amount exceeds maximum slashable amount");
        disputeManager.acceptDispute(disputeID, 6000 ether); // Slash service provider for 6000 GRT
    }

    // Cancel dispute

    function test_RevertIf_CallerIsNotFisherman_CancelDispute() public {
        createProvisionAndAllocte(allocationID);
        bytes32 disputeID = createIndexingDispute(allocationID);

        vm.prank(arbitrator);
        vm.expectRevert("Caller is not the Fisherman");
        disputeManager.cancelDispute(disputeID);
    }

    function testCancelDispute() public {
        createProvisionAndAllocte(allocationID);
        bytes32 disputeID = createIndexingDispute(allocationID);

        // skip to end of dispute period
        skip(disputePeriod + 1);

        vm.prank(fisherman);
        disputeManager.cancelDispute(disputeID);

        assertEq(graphToken.balanceOf(fisherman), 200 ether, "Fisherman should receive their deposit back.");
        assertEq(graphToken.balanceOf(serviceProvider), 10000 ether, "There's no slashing to the service provider.");
    }

    // Draw dispute

    function test_RevertIf_CallerIsNotArbitrator_DrawDispute() public {
        createProvisionAndAllocte(allocationID);
        bytes32 disputeID = createIndexingDispute(allocationID);

        // attempt to draw dispute as fisherman
        vm.prank(fisherman);
        vm.expectRevert("Caller is not the Arbitrator");
        disputeManager.drawDispute(disputeID);
    }

    function testDrawDispute() public {
        createProvisionAndAllocte(allocationID);
        bytes32 disputeID = createIndexingDispute(allocationID);

        vm.prank(arbitrator);
        disputeManager.drawDispute(disputeID);

        assertEq(graphToken.balanceOf(fisherman), 200 ether, "Fisherman should receive their deposit back.");
        assertEq(graphToken.balanceOf(serviceProvider), 10000 ether, "There's no slashing to the service provider.");
    }
}
