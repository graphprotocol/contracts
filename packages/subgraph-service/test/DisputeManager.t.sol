// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";

import { SubgraphDisputeManager } from "../contracts/SubgraphDisputeManager.sol";
import { ISubgraphDisputeManager } from "../contracts/interfaces/ISubgraphDisputeManager.sol";

import { SubgraphService } from "../contracts/SubgraphService.sol";

// Mocks

import "./mocks/MockGRTToken.sol";
import "./mocks/MockHorizonStaking.sol";

contract DisputeManagerTest is Test {
    SubgraphDisputeManager disputeManager;

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
    
    MockGRTToken graphToken;
    SubgraphService subgraphService;
    MockHorizonStaking staking;

    // Setup

    function setUp() public {
        arbitrator = address(0xA1);

        indexerPrivateKey = 0xB1;
        indexer = vm.addr(indexerPrivateKey);
        
        fishermanPrivateKey = 0xC1;
        fisherman = vm.addr(fishermanPrivateKey);
        
        allocationIDPrivateKey = 0xD1;
        allocationID = vm.addr(allocationIDPrivateKey);

        graphToken = new MockGRTToken();
        staking = new MockHorizonStaking(address(graphToken));
        address escrow = address(0xE1);
        address payments = address(0xE2);
        address tapVerifier = address(0xE3);

        disputeManager = new SubgraphDisputeManager(
            address(staking),
            address(graphToken),
            arbitrator,
            disputePeriod,
            minimumDeposit,
            fishermanRewardPercentage,
            maxSlashingPercentage
        );

        subgraphService = new SubgraphService(
            "SubgraphService",
            "1",
            address(staking),
            escrow,
            payments,
            address(disputeManager),
            tapVerifier,
            1000 ether
        );

        disputeManager.setSubgraphService(address(subgraphService));
    }

    // Helper functions

    function createProvisionAndAllocate(address _allocationID, uint256 tokens) private {
        vm.startPrank(indexer);
        graphToken.mint(indexer, tokens);
        staking.provision(tokens, address(subgraphService), 500000, 0);
        bytes32 subgraphDeployment = keccak256(abi.encodePacked("Subgraph Deployment ID"));
        bytes32 digest = subgraphService.encodeProof(indexer, _allocationID);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(allocationIDPrivateKey, digest);
        subgraphService.allocate(
            indexer,
            subgraphDeployment,
            tokens,
            _allocationID,
            keccak256(abi.encodePacked("metadata")),
            abi.encodePacked(r, s, v)
        );
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
        ISubgraphDisputeManager.Receipt memory receipt = ISubgraphDisputeManager.Receipt({
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
        ISubgraphDisputeManager.Receipt memory receipt1 = ISubgraphDisputeManager.Receipt({
            requestCID: requestCID,
            responseCID: responseCID1,
            subgraphDeploymentID: subgraphDeploymentID1
        });

        ISubgraphDisputeManager.Receipt memory receipt2 = ISubgraphDisputeManager.Receipt({
            requestCID: requestCID,
            responseCID: responseCID2,
            subgraphDeploymentID: subgraphDeploymentID2
        });

        bytes memory _attestationData1 = createAtestationData(receipt1, allocationIDPrivateKey);
        bytes memory _attestationData2 = createAtestationData(receipt2, allocationIDPrivateKey);
        return (_attestationData1, _attestationData2);
    }

    function createAtestationData(ISubgraphDisputeManager.Receipt memory receipt, uint256 signer) private view returns (bytes memory attestationData) {
        bytes32 digest = disputeManager.encodeHashReceipt(receipt);
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
        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);
        
        // Create another dispute with different fisherman
        address otherFisherman = address(0x5);
        uint256 tokens = 200 ether;
        vm.startPrank(otherFisherman);
        graphToken.mint(otherFisherman, tokens);
        graphToken.approve(address(disputeManager), tokens);
        bytes memory expectedError = abi.encodeWithSignature("SubgraphDisputeManagerDisputeAlreadyCreated(bytes32)", disputeID);
        vm.expectRevert(expectedError);
        disputeManager.createIndexingDispute(allocationID, tokens);
        vm.stopPrank();
    }

    function test_RevertIf_DepositUnderMinimum() public {
        // minimum deposit is 100 ether
        vm.startPrank(fisherman);
        graphToken.mint(fisherman, 50 ether);
        bytes memory expectedError = abi.encodeWithSignature("SubgraphDisputeManagerInsufficientDeposit(uint256,uint256)", 50 ether, 100 ether);
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
        bytes memory expectedError = abi.encodeWithSignature("SubgraphDisputeManagerIndexerNotFound(address)", allocationID);
        vm.expectRevert(expectedError);
        disputeManager.createIndexingDispute(allocationID, tokens);
        vm.stopPrank();
    }

    function test_RevertIf_ConflictingAttestationsResponsesAreTheSame() public {
        bytes32 requestCID = keccak256(abi.encodePacked("Request CID"));
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

        bytes memory expectedError = abi.encodeWithSignature(
            "SubgraphDisputeManagerNonConflictingAttestations(bytes32,bytes32,bytes32,bytes32,bytes32,bytes32)",
            requestCID, 
            responseCID, 
            subgraphDeploymentID, 
            requestCID, 
            responseCID, 
            subgraphDeploymentID
        );
        vm.expectRevert(expectedError);
        disputeManager.createQueryDisputeConflict(attestationData1, attestationData2);
    }

    function test_RevertIf_ConflictingAttestationsHaveDifferentSubgraph() public {
        bytes32 requestCID = keccak256(abi.encodePacked("Request CID"));
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
        bytes memory expectedError = abi.encodeWithSignature(
            "SubgraphDisputeManagerNonConflictingAttestations(bytes32,bytes32,bytes32,bytes32,bytes32,bytes32)",
            requestCID, 
            responseCID1, 
            subgraphDeploymentID1, 
            requestCID, 
            responseCID2, 
            subgraphDeploymentID2
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
        assertEq(graphToken.balanceOf(indexer), 5000 ether, "Service provider should have 5000 GRT slashed.");

        (, , , , , ISubgraphDisputeManager.DisputeStatus status1, ) = disputeManager.disputes(disputeID1);
        (, , , , , ISubgraphDisputeManager.DisputeStatus status2, ) = disputeManager.disputes(disputeID2);
        assertTrue(status1 == ISubgraphDisputeManager.DisputeStatus.Accepted, "Dispute 1 should be accepted.");
        assertTrue(status2 == ISubgraphDisputeManager.DisputeStatus.Rejected, "Dispute 2 should be rejected.");
    }

    function test_RevertIf_CallerIsNotArbitrator_AcceptDispute() public {
        createProvisionAndAllocate(allocationID, 10000 ether);

        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);

        // attempt to accept dispute as fisherman
        vm.prank(fisherman);
        vm.expectRevert(bytes4(keccak256("SubgraphDisputeManagerNotArbitrator()")));
        disputeManager.acceptDispute(disputeID, 5000 ether);
    }

    function test_RevertIf_SlashingOverMaxSlashPercentage() public {
        createProvisionAndAllocate(allocationID, 10000 ether);
        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);

        // max slashing percentage is 50%
        vm.prank(arbitrator);
        bytes memory expectedError = abi.encodeWithSignature("SubgraphDisputeManagerInvalidSlashAmount(uint256)", 6000 ether);
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

        assertEq(graphToken.balanceOf(indexer), 10000 ether, "There's no slashing to the indexer.");

        (, , , , , ISubgraphDisputeManager.DisputeStatus status1, ) = disputeManager.disputes(disputeID1);
        (, , , , , ISubgraphDisputeManager.DisputeStatus status2, ) = disputeManager.disputes(disputeID2);
        assertTrue(status1 == ISubgraphDisputeManager.DisputeStatus.Cancelled, "Dispute 1 should be cancelled.");
        assertTrue(status2 == ISubgraphDisputeManager.DisputeStatus.Cancelled, "Dispute 2 should be cancelled.");
    }

    function test_RevertIf_CallerIsNotFisherman_CancelDispute() public {
        createProvisionAndAllocate(allocationID, 10000 ether);
        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);

        vm.prank(arbitrator);
        vm.expectRevert(bytes4(keccak256("SubgraphDisputeManagerNotFisherman()")));
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

        assertEq(graphToken.balanceOf(indexer), 10000 ether, "There's no slashing to the indexer.");

        (, , , , , ISubgraphDisputeManager.DisputeStatus status1, ) = disputeManager.disputes(disputeID1);
        (, , , , , ISubgraphDisputeManager.DisputeStatus status2, ) = disputeManager.disputes(disputeID2);
        assertTrue(status1 == ISubgraphDisputeManager.DisputeStatus.Drawn, "Dispute 1 should be drawn.");
        assertTrue(status2 == ISubgraphDisputeManager.DisputeStatus.Drawn, "Dispute 2 should be drawn.");
    }

    function test_RevertIf_CallerIsNotArbitrator_DrawDispute() public {
        createProvisionAndAllocate(allocationID, 10000 ether);
        bytes32 disputeID = createIndexingDispute(allocationID, 200 ether);

        // attempt to draw dispute as fisherman
        vm.prank(fisherman);
        vm.expectRevert(bytes4(keccak256("SubgraphDisputeManagerNotArbitrator()")));
        disputeManager.drawDispute(disputeID);
    }
}
