// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { Controller } from "@graphprotocol/contracts/contracts/governance/Controller.sol";

import { DisputeManager } from "../contracts/DisputeManager.sol";
import { IDisputeManager } from "../contracts/interfaces/IDisputeManager.sol";
import { Attestation } from "../contracts/libraries/Attestation.sol";

import { SubgraphService } from "../contracts/SubgraphService.sol";

// Mocks

import "./mocks/MockGRTToken.sol";
import "./mocks/MockHorizonStaking.sol";
import "./mocks/MockRewardsManager.sol";

contract DisputeManagerTest is Test {
    DisputeManager disputeManager;

    address governor;
    address arbitrator;
    
    uint256 indexerPrivateKey;
    address indexer;
    
    uint256 fishermanPrivateKey;
    address fisherman;
    
    uint256 allocationIDPrivateKey;
    address allocationID;
    
    uint64 disputePeriod = 300; // 5 minutes
    uint256 minimumDeposit = 100 ether; // 100 GRT
    uint32 fishermanRewardPercentage = 100000; // 10%
    uint32 maxSlashingPercentage = 500000; // 50%
    
    Controller controller;
    MockGRTToken graphToken;
    SubgraphService subgraphService;
    MockHorizonStaking staking;
    MockRewardsManager rewardsManager;

    // Setup

    function setUp() public {
        governor = address(0xA1);
        arbitrator = address(0xA2);

        indexerPrivateKey = 0xB1;
        indexer = vm.addr(indexerPrivateKey);
        
        fishermanPrivateKey = 0xC1;
        fisherman = vm.addr(fishermanPrivateKey);
        
        allocationIDPrivateKey = 0xD1;
        allocationID = vm.addr(allocationIDPrivateKey);

        graphToken = new MockGRTToken();
        staking = new MockHorizonStaking(address(graphToken));
        rewardsManager = new MockRewardsManager();
        
        address tapVerifier = address(0xE3);
        address curation = address(0xE4);

        vm.startPrank(governor);
        controller = new Controller();
        controller.setContractProxy(keccak256("GraphToken"), address(graphToken));
        controller.setContractProxy(keccak256("Staking"), address(staking));
        controller.setContractProxy(keccak256("RewardsManager"), address(rewardsManager));
        vm.stopPrank();

        disputeManager = new DisputeManager(
            address(controller),
            arbitrator,
            disputePeriod,
            minimumDeposit,
            fishermanRewardPercentage,
            maxSlashingPercentage
        );

        subgraphService = new SubgraphService(
            address(controller),
            address(disputeManager),
            tapVerifier,
            curation,
            1000 ether,
            16
        );

        disputeManager.setSubgraphService(address(subgraphService));
    }

    // Helper functions

    function createProvisionAndAllocate(address _allocationID, uint256 tokens) private {
        vm.startPrank(indexer);
        graphToken.mint(indexer, tokens);
        staking.provision(tokens, address(subgraphService), 500000, 300);
        bytes32 subgraphDeployment = keccak256(abi.encodePacked("Subgraph Deployment ID"));
        bytes32 digest = subgraphService.encodeAllocationProof(indexer, _allocationID);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(allocationIDPrivateKey, digest);

        subgraphService.register(
            indexer,
            abi.encode("url", "geoHash")
        );

        bytes memory data = abi.encode(
            subgraphDeployment,
            tokens,
            _allocationID,
            abi.encodePacked(r, s, v)
        );
        subgraphService.startService(indexer, data);
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
        Attestation.Receipt memory receipt = Attestation.Receipt({
            requestCID: keccak256(abi.encodePacked("Request CID")),
            responseCID: keccak256(abi.encodePacked("Response CID")),
            subgraphDeploymentId: keccak256(abi.encodePacked("Subgraph Deployment ID"))
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
        bytes32 subgraphDeploymentId1,
        bytes32 responseCID2,
        bytes32 subgraphDeploymentId2
    ) private view returns (bytes memory attestationData1, bytes memory attestationData2) {
        bytes32 requestCID = keccak256(abi.encodePacked("Request CID"));
        Attestation.Receipt memory receipt1 = Attestation.Receipt({
            requestCID: requestCID,
            responseCID: responseCID1,
            subgraphDeploymentId: subgraphDeploymentId1
        });

        Attestation.Receipt memory receipt2 = Attestation.Receipt({
            requestCID: requestCID,
            responseCID: responseCID2,
            subgraphDeploymentId: subgraphDeploymentId2
        });

        bytes memory _attestationData1 = createAtestationData(receipt1, allocationIDPrivateKey);
        bytes memory _attestationData2 = createAtestationData(receipt2, allocationIDPrivateKey);
        return (_attestationData1, _attestationData2);
    }

    function createAtestationData(Attestation.Receipt memory receipt, uint256 signer) private view returns (bytes memory attestationData) {
        bytes32 digest = disputeManager.encodeReceipt(receipt);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, digest);
        
        return abi.encodePacked(receipt.requestCID, receipt.responseCID, receipt.subgraphDeploymentId, r, s, v);
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
        bytes32 subgraphDeploymentId = keccak256(abi.encodePacked("Subgraph Deployment ID"));

        (bytes memory attestationData1, bytes memory attestationData2) =
            createConflictingAttestations(
                responseCID1, 
                subgraphDeploymentId, 
                responseCID2, 
                subgraphDeploymentId
            );

        vm.prank(fisherman);
        (bytes32 disputeID1, bytes32 disputeID2) =
            disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);
        assertTrue(disputeManager.isDisputeCreated(disputeID1), "Dispute 1 should be created.");
        assertTrue(disputeManager.isDisputeCreated(disputeID2), "Dispute 2 should be created.");
    }

    function test_RevertWhen_DisputeAlreadyCreated() public {
        createProvisionAndAllocate(allocationID, 10000 ether);
        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);
        
        // Create another dispute with different fisherman
        address otherFisherman = address(0x5);
        uint256 tokens = 200 ether;
        vm.startPrank(otherFisherman);
        graphToken.mint(otherFisherman, tokens);
        graphToken.approve(address(disputeManager), tokens);
        bytes memory expectedError = abi.encodeWithSignature("DisputeManagerDisputeAlreadyCreated(bytes32)", disputeID);
        vm.expectRevert(expectedError);
        disputeManager.createIndexingDispute(allocationID, tokens);
        vm.stopPrank();
    }

    function test_RevertIf_DepositUnderMinimum() public {
        // minimum deposit is 100 ether
        vm.startPrank(fisherman);
        graphToken.mint(fisherman, 50 ether);
        bytes memory expectedError = abi.encodeWithSignature("DisputeManagerInsufficientDeposit(uint256,uint256)", 50 ether, 100 ether);
        vm.expectRevert(expectedError);
        disputeManager.createIndexingDispute(allocationID, 50 ether);
        vm.stopPrank();
    }

    function test_RevertIf_AllocationDoesNotExist() public {
        // create dispute without an existing allocation
        uint256 tokens = 200 ether;
        vm.startPrank(fisherman);
        graphToken.mint(fisherman, tokens);
        graphToken.approve(address(disputeManager), tokens);
        bytes memory expectedError = abi.encodeWithSignature("DisputeManagerIndexerNotFound(address)", allocationID);
        vm.expectRevert(expectedError);
        disputeManager.createIndexingDispute(allocationID, tokens);
        vm.stopPrank();
    }

    function test_RevertIf_ConflictingAttestationsResponsesAreTheSame() public {
        bytes32 requestCID = keccak256(abi.encodePacked("Request CID"));
        bytes32 responseCID = keccak256(abi.encodePacked("Response CID"));
        bytes32 subgraphDeploymentId = keccak256(abi.encodePacked("Subgraph Deployment ID"));

        (bytes memory attestationData1, bytes memory attestationData2) =
            createConflictingAttestations(
                responseCID,
                subgraphDeploymentId,
                responseCID,
                subgraphDeploymentId
            );

        vm.prank(fisherman);

        bytes memory expectedError = abi.encodeWithSignature(
            "DisputeManagerNonConflictingAttestations(bytes32,bytes32,bytes32,bytes32,bytes32,bytes32)",
            requestCID, 
            responseCID, 
            subgraphDeploymentId, 
            requestCID, 
            responseCID, 
            subgraphDeploymentId
        );
        vm.expectRevert(expectedError);
        disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);
    }

    function test_RevertIf_ConflictingAttestationsHaveDifferentSubgraph() public {
        bytes32 requestCID = keccak256(abi.encodePacked("Request CID"));
        bytes32 responseCID1 = keccak256(abi.encodePacked("Response CID 1"));
        bytes32 responseCID2 = keccak256(abi.encodePacked("Response CID 2"));
        bytes32 subgraphDeploymentId1 = keccak256(abi.encodePacked("Subgraph Deployment ID 1"));
        bytes32 subgraphDeploymentId2 = keccak256(abi.encodePacked("Subgraph Deployment ID 2"));

        (bytes memory attestationData1, bytes memory attestationData2) =
            createConflictingAttestations(
                responseCID1, 
                subgraphDeploymentId1, 
                responseCID2, 
                subgraphDeploymentId2
            );

        vm.prank(fisherman);
        bytes memory expectedError = abi.encodeWithSignature(
            "DisputeManagerNonConflictingAttestations(bytes32,bytes32,bytes32,bytes32,bytes32,bytes32)",
            requestCID, 
            responseCID1, 
            subgraphDeploymentId1, 
            requestCID, 
            responseCID2, 
            subgraphDeploymentId2
        );
        vm.expectRevert(expectedError);
        disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);
    }

    // Accept dispute

    function testAcceptIndexingDispute() public {
        createProvisionAndAllocate(allocationID, 10000 ether);
        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);

        vm.prank(arbitrator);
        disputeManager.acceptDispute(disputeID, 5000 ether);

        assertEq(graphToken.balanceOf(fisherman), 700 ether, "Fisherman should receive 50% of slashed tokens.");
        assertEq(graphToken.balanceOf(indexer), 5000 ether, "Service provider should have 5000 GRT slashed.");
    }

    function testAcceptQueryDispute() public {
        createProvisionAndAllocate(allocationID, 10000 ether);
        bytes32 disputeID = createQueryDispute(200 ether);

        vm.prank(arbitrator);
        disputeManager.acceptDispute(disputeID, 5000 ether);

        assertEq(graphToken.balanceOf(fisherman), 700 ether, "Fisherman should receive 50% of slashed tokens.");
        assertEq(graphToken.balanceOf(indexer), 5000 ether, "Service provider should have 5000 GRT slashed.");
    }

    function testAcceptQueryDisputeConflicting() public {
        createProvisionAndAllocate(allocationID, 10000 ether);

        bytes32 responseCID1 = keccak256(abi.encodePacked("Response CID 1"));
        bytes32 responseCID2 = keccak256(abi.encodePacked("Response CID 2"));
        bytes32 subgraphDeploymentId = keccak256(abi.encodePacked("Subgraph Deployment ID"));

        (bytes memory attestationData1, bytes memory attestationData2) =
            createConflictingAttestations(
                responseCID1, 
                subgraphDeploymentId, 
                responseCID2, 
                subgraphDeploymentId
            );

        vm.prank(fisherman);
        (bytes32 disputeID1, bytes32 disputeID2) =
            disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);
        
        vm.prank(arbitrator);
        disputeManager.acceptDispute(disputeID1, 5000 ether);

        assertEq(graphToken.balanceOf(fisherman), 500 ether, "Fisherman should receive 50% of slashed tokens.");
        assertEq(graphToken.balanceOf(indexer), 5000 ether, "Service provider should have 5000 GRT slashed.");

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
        vm.expectRevert(bytes4(keccak256("DisputeManagerNotArbitrator()")));
        disputeManager.acceptDispute(disputeID, 5000 ether);
    }

    function test_RevertIf_SlashingOverMaxSlashPercentage() public {
        createProvisionAndAllocate(allocationID, 10000 ether);
        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);

        // max slashing percentage is 50%
        vm.prank(arbitrator);
        bytes memory expectedError = abi.encodeWithSignature("DisputeManagerInvalidSlashAmount(uint256)", 6000 ether);
        vm.expectRevert(expectedError);
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
        assertEq(graphToken.balanceOf(indexer), 10000 ether, "There's no slashing to the indexer.");
    }

    function testCancelQueryDisputeConflicting() public {
        createProvisionAndAllocate(allocationID, 10000 ether);

        bytes32 responseCID1 = keccak256(abi.encodePacked("Response CID 1"));
        bytes32 responseCID2 = keccak256(abi.encodePacked("Response CID 2"));
        bytes32 subgraphDeploymentId = keccak256(abi.encodePacked("Subgraph Deployment ID"));

        (bytes memory attestationData1, bytes memory attestationData2) =
            createConflictingAttestations(
                responseCID1, 
                subgraphDeploymentId, 
                responseCID2, 
                subgraphDeploymentId
            );

        vm.prank(fisherman);
        (bytes32 disputeID1, bytes32 disputeID2) =
            disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);

        // skip to end of dispute period
        skip(disputePeriod + 1);
        
        vm.prank(fisherman);
        disputeManager.cancelDispute(disputeID1);

        assertEq(graphToken.balanceOf(indexer), 10000 ether, "There's no slashing to the indexer.");

        (, , , , , IDisputeManager.DisputeStatus status1, ) = disputeManager.disputes(disputeID1);
        (, , , , , IDisputeManager.DisputeStatus status2, ) = disputeManager.disputes(disputeID2);
        assertTrue(status1 == IDisputeManager.DisputeStatus.Cancelled, "Dispute 1 should be cancelled.");
        assertTrue(status2 == IDisputeManager.DisputeStatus.Cancelled, "Dispute 2 should be cancelled.");
    }

    function test_RevertIf_CallerIsNotFisherman_CancelDispute() public {
        createProvisionAndAllocate(allocationID, 10000 ether);
        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);

        vm.prank(arbitrator);
        vm.expectRevert(bytes4(keccak256("DisputeManagerNotFisherman()")));
        disputeManager.cancelDispute(disputeID);
    }

    // Draw dispute

    function testDrawDispute() public {
        createProvisionAndAllocate(allocationID, 10000 ether);
        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);

        vm.prank(arbitrator);
        disputeManager.drawDispute(disputeID);

        assertEq(graphToken.balanceOf(fisherman), 200 ether, "Fisherman should receive their deposit back.");
        assertEq(graphToken.balanceOf(indexer), 10000 ether, "There's no slashing to the indexer.");
    }

    function testDrawQueryDisputeConflicting() public {
        createProvisionAndAllocate(allocationID, 10000 ether);

        bytes32 responseCID1 = keccak256(abi.encodePacked("Response CID 1"));
        bytes32 responseCID2 = keccak256(abi.encodePacked("Response CID 2"));
        bytes32 subgraphDeploymentId = keccak256(abi.encodePacked("Subgraph Deployment ID"));

        (bytes memory attestationData1, bytes memory attestationData2) =
            createConflictingAttestations(
                responseCID1, 
                subgraphDeploymentId, 
                responseCID2, 
                subgraphDeploymentId
            );

        vm.prank(fisherman);
        (bytes32 disputeID1, bytes32 disputeID2) =
            disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);
        
        vm.prank(arbitrator);
        disputeManager.drawDispute(disputeID1);

        assertEq(graphToken.balanceOf(indexer), 10000 ether, "There's no slashing to the indexer.");

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
        vm.expectRevert(bytes4(keccak256("DisputeManagerNotArbitrator()")));
        disputeManager.drawDispute(disputeID);
    }
}
