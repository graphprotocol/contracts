// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";

import "../contracts/disputes/DisputeManager.sol";
import "../contracts/disputes/IDisputeManager.sol";

// Mocks

import "./mocks/MockGRTToken.sol";
import "./mocks/MockSubgraphService.sol";
import "./mocks/MockHorizonStaking.sol";
import "./utils/QueryDisputeSignUtils.sol";

contract DisputeManagerTest is Test {
    DisputeManager disputeManager;

    address arbitrator;
    
    uint256 serviceProviderPrivateKey;
    address serviceProvider;
    
    uint256 fishermanPrivateKey;
    address fisherman;
    
    uint256 allocationIDPrivateKey;
    address allocationID;
    
    uint64 disputePeriod = 300; // 5 minutes
    uint256 minimumDeposit = 100 ether; // 100 GRT
    uint32 fishermanRewardPercentage = 100000; // 10%
    uint32 maxSlashingPercentage = 500000; // 50%
    
    MockGRTToken graphToken;
    MockSubgraphService subgraphService;
    MockHorizonStaking staking;

    QueryDisputeSignUtils queryDisputeSignUtils;

    // Setup

    function setUp() public {
        arbitrator = address(0xA1);

        serviceProviderPrivateKey = 0xB1;
        serviceProvider = vm.addr(serviceProviderPrivateKey);
        
        fishermanPrivateKey = 0xC1;
        fisherman = vm.addr(fishermanPrivateKey);
        
        allocationIDPrivateKey = 0xD1;
        allocationID = vm.addr(allocationIDPrivateKey);

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

        queryDisputeSignUtils = new QueryDisputeSignUtils(address(disputeManager));
    }

    // Helper functions

    function createProvisionAndAllocate(address _allocationID, uint256 tokens) private {
        vm.startPrank(serviceProvider);
        graphToken.mint(serviceProvider, tokens);
        staking.provision(tokens, address(subgraphService), 500000, 0);
        bytes32 subgraphDeployment = keccak256(abi.encodePacked("Subgraph Deployment ID"));
        subgraphService.allocate(serviceProvider, subgraphDeployment, tokens, _allocationID);
        vm.stopPrank();
    }

    function createIndexingDispute(address _allocationID, uint256 tokens) private returns (bytes32 disputeID) {
        vm.startPrank(fisherman);
        graphToken.mint(fisherman, tokens);
        graphToken.approve(address(disputeManager), tokens);
        bytes32 _disputeID = disputeManager.createIndexingDispute(_allocationID, tokens);
        vm.stopPrank();
        return _disputeID;
    }

    function createQueryDispute(uint256 tokens) private returns (bytes32 disputeID) {
        IDisputeManager.Receipt memory receipt = IDisputeManager.Receipt({
            requestCID: keccak256(abi.encodePacked("Request CID")),
            responseCID: keccak256(abi.encodePacked("Response CID")),
            subgraphDeploymentID: keccak256(abi.encodePacked("Subgraph Deployment ID"))
        });
        bytes memory attestationData = createAtestationData(receipt, allocationIDPrivateKey);
        
        vm.startPrank(fisherman);
        graphToken.mint(fisherman, tokens);
        graphToken.approve(address(disputeManager), tokens);
        bytes32 _disputeID = disputeManager.createQueryDispute(attestationData, tokens);
        vm.stopPrank();
        return _disputeID;
    }

    function createConflictingAttestations(
        bytes32 responseCID1,
        bytes32 subgraphDeploymentID1,
        bytes32 responseCID2,
        bytes32 subgraphDeploymentID2
    ) private view returns (bytes memory attestationData1, bytes memory attestationData2) {
        bytes32 requestCID = keccak256(abi.encodePacked("Request CID"));
        IDisputeManager.Receipt memory receipt1 = IDisputeManager.Receipt({
            requestCID: requestCID,
            responseCID: responseCID1,
            subgraphDeploymentID: subgraphDeploymentID1
        });

        IDisputeManager.Receipt memory receipt2 = IDisputeManager.Receipt({
            requestCID: requestCID,
            responseCID: responseCID2,
            subgraphDeploymentID: subgraphDeploymentID2
        });

        bytes memory _attestationData1 = createAtestationData(receipt1, allocationIDPrivateKey);
        bytes memory _attestationData2 = createAtestationData(receipt2, allocationIDPrivateKey);
        return (_attestationData1, _attestationData2);
    }

    function createAtestationData(IDisputeManager.Receipt memory receipt, uint256 signer) private view returns (bytes memory attestationData) {
        bytes32 digest = queryDisputeSignUtils.getMessageHash(receipt);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, digest);
        
        return abi.encodePacked(receipt.requestCID, receipt.responseCID, receipt.subgraphDeploymentID, r, s, v);
    }

    // Tests

    // Create dispute

    function testCreateIndexingDispute() public {
        createProvisionAndAllocate(allocationID, 10000 ether);

        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);
        assertTrue(disputeManager.isDisputeCreated(disputeID), "Dispute should be created.");
    }

    function testCreateQueryDispute() public {
        createProvisionAndAllocate(allocationID, 10000 ether);

        bytes32 disputeID = createQueryDispute(200 ether);
        assertTrue(disputeManager.isDisputeCreated(disputeID), "Dispute should be created.");
    }

    function testCreateQueryDisputeConflict() public {
        createProvisionAndAllocate(allocationID, 10000 ether);

        bytes32 responseCID1 = keccak256(abi.encodePacked("Response CID 1"));
        bytes32 responseCID2 = keccak256(abi.encodePacked("Response CID 2"));
        bytes32 subgraphDeploymentID = keccak256(abi.encodePacked("Subgraph Deployment ID"));

        (bytes memory attestationData1, bytes memory attestationData2) =
            createConflictingAttestations(
                responseCID1, 
                subgraphDeploymentID, 
                responseCID2, 
                subgraphDeploymentID
            );

        vm.prank(fisherman);
        (bytes32 disputeID1, bytes32 disputeID2) =
            disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);
        assertTrue(disputeManager.isDisputeCreated(disputeID1), "Dispute 1 should be created.");
        assertTrue(disputeManager.isDisputeCreated(disputeID2), "Dispute 2 should be created.");
    }

    function test_RevertWhen_DisputeAlreadyCreated() public {
        createProvisionAndAllocate(allocationID, 10000 ether);
        createIndexingDispute(allocationID, 200 ether);
        
        // Create another dispute with different fisherman
        address otherFisherman = address(0x5);
        uint256 tokens = 200 ether;
        vm.startPrank(otherFisherman);
        graphToken.mint(otherFisherman, tokens);
        graphToken.approve(address(disputeManager), tokens);
        vm.expectRevert("Dispute already created");
        disputeManager.createIndexingDispute(allocationID, tokens);
        vm.stopPrank();
    }

    function test_RevertIf_DepositUnderMinimum() public {
        // minimum deposit is 100 ether
        vm.startPrank(fisherman);
        graphToken.mint(fisherman, 50 ether);
        vm.expectRevert("Dispute deposit is under minimum required");
        disputeManager.createIndexingDispute(allocationID, 50 ether);
        vm.stopPrank();
    }

    function test_RevertIf_AllocationDoesNotExist() public {
        // create dispute without an existing allocation
        uint256 tokens = 200 ether;
        vm.startPrank(fisherman);
        graphToken.mint(fisherman, tokens);
        graphToken.approve(address(disputeManager), tokens);
        vm.expectRevert("Dispute allocation must exist");
        disputeManager.createIndexingDispute(allocationID, tokens);
        vm.stopPrank();
    }

    function test_RevertIf_ConflictingAttestationsResponsesAreTheSame() public {
        bytes32 responseCID = keccak256(abi.encodePacked("Response CID"));
        bytes32 subgraphDeploymentID = keccak256(abi.encodePacked("Subgraph Deployment ID"));

        (bytes memory attestationData1, bytes memory attestationData2) =
            createConflictingAttestations(
                responseCID,
                subgraphDeploymentID,
                responseCID,
                subgraphDeploymentID
            );

        vm.prank(fisherman);
        vm.expectRevert("Attestations must be in conflict");
        disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);
    }

    function test_RevertIf_ConflictingAttestationsHaveDifferentSubgraph() public {
        bytes32 responseCID1 = keccak256(abi.encodePacked("Response CID 1"));
        bytes32 responseCID2 = keccak256(abi.encodePacked("Response CID 2"));
        bytes32 subgraphDeploymentID1 = keccak256(abi.encodePacked("Subgraph Deployment ID 1"));
        bytes32 subgraphDeploymentID2 = keccak256(abi.encodePacked("Subgraph Deployment ID 2"));

        (bytes memory attestationData1, bytes memory attestationData2) =
            createConflictingAttestations(
                responseCID1, 
                subgraphDeploymentID1, 
                responseCID2, 
                subgraphDeploymentID2
            );

        vm.prank(fisherman);
        vm.expectRevert("Attestations must be in conflict");
        disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);
    }

    // Accept dispute

    function testAcceptIndexingDispute() public {
        createProvisionAndAllocate(allocationID, 10000 ether);
        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);

        vm.prank(arbitrator);
        disputeManager.acceptDispute(disputeID, 5000 ether);

        assertEq(graphToken.balanceOf(fisherman), 700 ether, "Fisherman should receive 50% of slashed tokens.");
        assertEq(graphToken.balanceOf(serviceProvider), 5000 ether, "Service provider should have 5000 GRT slashed.");
    }

    function testAcceptQueryDispute() public {
        createProvisionAndAllocate(allocationID, 10000 ether);
        bytes32 disputeID = createQueryDispute(200 ether);

        vm.prank(arbitrator);
        disputeManager.acceptDispute(disputeID, 5000 ether);

        assertEq(graphToken.balanceOf(fisherman), 700 ether, "Fisherman should receive 50% of slashed tokens.");
        assertEq(graphToken.balanceOf(serviceProvider), 5000 ether, "Service provider should have 5000 GRT slashed.");
    }

    function testAcceptQueryDisputeConflicting() public {
        createProvisionAndAllocate(allocationID, 10000 ether);

        bytes32 responseCID1 = keccak256(abi.encodePacked("Response CID 1"));
        bytes32 responseCID2 = keccak256(abi.encodePacked("Response CID 2"));
        bytes32 subgraphDeploymentID = keccak256(abi.encodePacked("Subgraph Deployment ID"));

        (bytes memory attestationData1, bytes memory attestationData2) =
            createConflictingAttestations(
                responseCID1, 
                subgraphDeploymentID, 
                responseCID2, 
                subgraphDeploymentID
            );

        vm.prank(fisherman);
        (bytes32 disputeID1, bytes32 disputeID2) =
            disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);
        
        vm.prank(arbitrator);
        disputeManager.acceptDispute(disputeID1, 5000 ether);

        assertEq(graphToken.balanceOf(fisherman), 500 ether, "Fisherman should receive 50% of slashed tokens.");
        assertEq(graphToken.balanceOf(serviceProvider), 5000 ether, "Service provider should have 5000 GRT slashed.");

        (, , , , , IDisputeManager.DisputeStatus status1, ) = disputeManager.disputes(disputeID1);
        (, , , , , IDisputeManager.DisputeStatus status2, ) = disputeManager.disputes(disputeID2);
        assertTrue(status1 == IDisputeManager.DisputeStatus.Accepted, "Dispute 1 should be accepted.");
        assertTrue(status2 == IDisputeManager.DisputeStatus.Rejected, "Dispute 2 should be rejected.");
    }

    function test_RevertIf_CallerIsNotArbitrator_AcceptDispute() public {
        createProvisionAndAllocate(allocationID, 10000 ether);

        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);

        // attempt to accept dispute as fisherman
        vm.prank(fisherman);
        vm.expectRevert("Caller is not the Arbitrator");
        disputeManager.acceptDispute(disputeID, 5000 ether);
    }

    function test_RevertIf_SlashingOverMaxSlashPercentage() public {
        createProvisionAndAllocate(allocationID, 10000 ether);
        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);

        // max slashing percentage is 50%
        vm.prank(arbitrator);
        vm.expectRevert("Slash amount exceeds maximum slashable amount");
        disputeManager.acceptDispute(disputeID, 6000 ether);
    }

    // Cancel dispute

    function testCancelDispute() public {
        createProvisionAndAllocate(allocationID, 10000 ether);
        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);

        // skip to end of dispute period
        skip(disputePeriod + 1);

        vm.prank(fisherman);
        disputeManager.cancelDispute(disputeID);

        assertEq(graphToken.balanceOf(fisherman), 200 ether, "Fisherman should receive their deposit back.");
        assertEq(graphToken.balanceOf(serviceProvider), 10000 ether, "There's no slashing to the service provider.");
    }

    function testCancelQueryDisputeConflicting() public {
        createProvisionAndAllocate(allocationID, 10000 ether);

        bytes32 responseCID1 = keccak256(abi.encodePacked("Response CID 1"));
        bytes32 responseCID2 = keccak256(abi.encodePacked("Response CID 2"));
        bytes32 subgraphDeploymentID = keccak256(abi.encodePacked("Subgraph Deployment ID"));

        (bytes memory attestationData1, bytes memory attestationData2) =
            createConflictingAttestations(
                responseCID1, 
                subgraphDeploymentID, 
                responseCID2, 
                subgraphDeploymentID
            );

        vm.prank(fisherman);
        (bytes32 disputeID1, bytes32 disputeID2) =
            disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);

        // skip to end of dispute period
        skip(disputePeriod + 1);
        
        vm.prank(fisherman);
        disputeManager.cancelDispute(disputeID1);

        assertEq(graphToken.balanceOf(serviceProvider), 10000 ether, "There's no slashing to the service provider.");

        (, , , , , IDisputeManager.DisputeStatus status1, ) = disputeManager.disputes(disputeID1);
        (, , , , , IDisputeManager.DisputeStatus status2, ) = disputeManager.disputes(disputeID2);
        assertTrue(status1 == IDisputeManager.DisputeStatus.Cancelled, "Dispute 1 should be cancelled.");
        assertTrue(status2 == IDisputeManager.DisputeStatus.Cancelled, "Dispute 2 should be cancelled.");
    }

    function test_RevertIf_CallerIsNotFisherman_CancelDispute() public {
        createProvisionAndAllocate(allocationID, 10000 ether);
        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);

        vm.prank(arbitrator);
        vm.expectRevert("Caller is not the Fisherman");
        disputeManager.cancelDispute(disputeID);
    }

    // Draw dispute

    function testDrawDispute() public {
        createProvisionAndAllocate(allocationID, 10000 ether);
        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);

        vm.prank(arbitrator);
        disputeManager.drawDispute(disputeID);

        assertEq(graphToken.balanceOf(fisherman), 200 ether, "Fisherman should receive their deposit back.");
        assertEq(graphToken.balanceOf(serviceProvider), 10000 ether, "There's no slashing to the service provider.");
    }

    function testDrawQueryDisputeConflicting() public {
        createProvisionAndAllocate(allocationID, 10000 ether);

        bytes32 responseCID1 = keccak256(abi.encodePacked("Response CID 1"));
        bytes32 responseCID2 = keccak256(abi.encodePacked("Response CID 2"));
        bytes32 subgraphDeploymentID = keccak256(abi.encodePacked("Subgraph Deployment ID"));

        (bytes memory attestationData1, bytes memory attestationData2) =
            createConflictingAttestations(
                responseCID1, 
                subgraphDeploymentID, 
                responseCID2, 
                subgraphDeploymentID
            );

        vm.prank(fisherman);
        (bytes32 disputeID1, bytes32 disputeID2) =
            disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);
        
        vm.prank(arbitrator);
        disputeManager.drawDispute(disputeID1);

        assertEq(graphToken.balanceOf(serviceProvider), 10000 ether, "There's no slashing to the service provider.");

        (, , , , , IDisputeManager.DisputeStatus status1, ) = disputeManager.disputes(disputeID1);
        (, , , , , IDisputeManager.DisputeStatus status2, ) = disputeManager.disputes(disputeID2);
        assertTrue(status1 == IDisputeManager.DisputeStatus.Drawn, "Dispute 1 should be drawn.");
        assertTrue(status2 == IDisputeManager.DisputeStatus.Drawn, "Dispute 2 should be drawn.");
    }

    function test_RevertIf_CallerIsNotArbitrator_DrawDispute() public {
        createProvisionAndAllocate(allocationID, 10000 ether);
        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);

        // attempt to draw dispute as fisherman
        vm.prank(fisherman);
        vm.expectRevert("Caller is not the Arbitrator");
        disputeManager.drawDispute(disputeID);
    }
}
