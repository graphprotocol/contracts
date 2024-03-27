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
    uint256 minimumDeposit = 100 ether; // 100 GRT
    uint32 fishermanRewardPercentage = 100000; // 10%
    uint32 maxSlashingPercentage = 500000; // 50%
    MockGRTToken graphToken;
    MockSubgraphService subgraphService;
    MockHorizonStaking staking;

    function setUp() public {
        graphToken = new MockGRTToken();
        subgraphService = new MockSubgraphService(address(graphToken));
        staking = new MockHorizonStaking();

        disputeManager = new DisputeManager(
            subgraphService,
            staking,
            graphToken,
            arbitrator,
            minimumDeposit,
            fishermanRewardPercentage,
            maxSlashingPercentage
        );
    }

    function testGetVerifierCut() public view {
        // Set the fisherman reward percentage if necessary
        // disputeManager.setFishermanRewardPercentage(verifierCut);

        uint256 cut = disputeManager.getVerifierCut();
        assertEq(cut, fishermanRewardPercentage, "Verifier cut does not match expected value.");
    }

    function testAcceptDispute() public {
        address serviceProvider = address(0x2);
        address fisherman = address(0x3);
        address allocationID = address(0x4);

        console.log("Staking: ", address(staking));
        console.log("Subgraph Service: ", address(subgraphService));
        console.log("Graph Token: ", address(graphToken));

        console.log("Service provider: ", serviceProvider);
        console.log("Fisherman: ", fisherman);
        console.log("Allocation ID: ", allocationID);

        // service provider actions
        vm.startPrank(serviceProvider);
        graphToken.mint(serviceProvider, 10000 ether); // 10,000 GRT
        staking.provision(10000 ether, address(subgraphService), 500000, 0);
        bytes32 subgraphDeployment = keccak256(abi.encodePacked("Subgraph Deployment ID"));
        subgraphService.allocate(serviceProvider, subgraphDeployment, 1000 ether, allocationID); // 10,000 GRT
        vm.stopPrank();
      
        // fisherman actions
        vm.startPrank(fisherman);
        graphToken.mint(fisherman, 200 ether); // 200 GRT
        graphToken.approve(address(disputeManager), 200 ether); // Allow DisputeManager to transfer 1000 GRT
        bytes32 disputeID = disputeManager.createIndexingDispute(allocationID, 200 ether); // Deposit 200 GRT
        vm.stopPrank();

        console.log("Dispute ID: %s", vm.toString(disputeID));

        // arbitrator actions
        vm.prank(arbitrator);
        disputeManager.acceptDispute(disputeID, 5000 ether); // Slash service provider for 5000 GRT

        assertEq(graphToken.balanceOf(fisherman), 700 ether, "Fisherman should receive 50% of slashed tokens.");
    }
}
