// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "../../contracts/interfaces/IDisputeManager.sol";
import { Attestation } from "../../contracts/libraries/Attestation.sol";
import { Allocation } from "../../contracts/libraries/Allocation.sol";
import { IDisputeManager } from "../../contracts/interfaces/IDisputeManager.sol";

import { SubgraphServiceSharedTest } from "../shared/SubgraphServiceShared.t.sol";

contract DisputeManagerTest is SubgraphServiceSharedTest {
    using PPMMath for uint256;

    /*
     * MODIFIERS
     */

    modifier useGovernor() {
        vm.startPrank(users.governor);
        _;
        vm.stopPrank();
    }

    modifier useFisherman() {
        vm.startPrank(users.fisherman);
        _;
        vm.stopPrank();
    }

    /*
     * ACTIONS
     */

    function _setArbitrator(address _arbitrator) internal {
        vm.expectEmit(address(disputeManager));
        emit IDisputeManager.ArbitratorSet(_arbitrator);
        disputeManager.setArbitrator(_arbitrator);
        assertEq(disputeManager.arbitrator(), _arbitrator, "Arbitrator should be set.");
    }

    function _setFishermanRewardCut(uint32 _fishermanRewardCut) internal {
        vm.expectEmit(address(disputeManager));
        emit IDisputeManager.FishermanRewardCutSet(_fishermanRewardCut);
        disputeManager.setFishermanRewardCut(_fishermanRewardCut);
        assertEq(disputeManager.fishermanRewardCut(), _fishermanRewardCut, "Fisherman reward cut should be set.");
    }

    function _setMaxSlashingCut(uint32 _maxSlashingCut) internal {
        vm.expectEmit(address(disputeManager));
        emit IDisputeManager.MaxSlashingCutSet(_maxSlashingCut);
        disputeManager.setMaxSlashingCut(_maxSlashingCut);
        assertEq(disputeManager.maxSlashingCut(), _maxSlashingCut, "Max slashing cut should be set.");
    }

    function _setDisputeDeposit(uint256 _disputeDeposit) internal {
        vm.expectEmit(address(disputeManager));
        emit IDisputeManager.DisputeDepositSet(_disputeDeposit);
        disputeManager.setDisputeDeposit(_disputeDeposit);
        assertEq(disputeManager.disputeDeposit(), _disputeDeposit, "Dispute deposit should be set.");
    }

    function _setSubgraphService(address _subgraphService) internal {
        vm.expectEmit(address(disputeManager));
        emit IDisputeManager.SubgraphServiceSet(_subgraphService);
        disputeManager.setSubgraphService(_subgraphService);
        assertEq(address(disputeManager.subgraphService()), _subgraphService, "Subgraph service should be set.");
    }

    function _createIndexingDispute(address _allocationId, bytes32 _poi) internal returns (bytes32) {
        (, address fisherman, ) = vm.readCallers();
        bytes32 expectedDisputeId = keccak256(abi.encodePacked(_allocationId, _poi));
        uint256 disputeDeposit = disputeManager.disputeDeposit();
        uint256 beforeFishermanBalance = token.balanceOf(fisherman);
        Allocation.State memory alloc = subgraphService.getAllocation(_allocationId);
        uint256 stakeSnapshot = disputeManager.getStakeSnapshot(alloc.indexer);

        // Approve the dispute deposit
        token.approve(address(disputeManager), disputeDeposit);

        vm.expectEmit(address(disputeManager));
        emit IDisputeManager.IndexingDisputeCreated(
            expectedDisputeId,
            alloc.indexer,
            fisherman,
            disputeDeposit,
            _allocationId,
            _poi,
            stakeSnapshot
        );

        // Create the indexing dispute
        bytes32 _disputeId = disputeManager.createIndexingDispute(_allocationId, _poi);

        // Check that the dispute was created and that it has the correct ID
        assertTrue(disputeManager.isDisputeCreated(_disputeId), "Dispute should be created.");
        assertEq(expectedDisputeId, _disputeId, "Dispute ID should match");

        // Check dispute values
        IDisputeManager.Dispute memory dispute = _getDispute(_disputeId);
        assertEq(dispute.indexer, alloc.indexer, "Indexer should match");
        assertEq(dispute.fisherman, fisherman, "Fisherman should match");
        assertEq(dispute.deposit, disputeDeposit, "Deposit should match");
        assertEq(dispute.relatedDisputeId, bytes32(0), "Related dispute ID should be empty");
        assertEq(
            uint8(dispute.disputeType),
            uint8(IDisputeManager.DisputeType.IndexingDispute),
            "Dispute type should be indexing"
        );
        assertEq(
            uint8(dispute.status),
            uint8(IDisputeManager.DisputeStatus.Pending),
            "Dispute status should be pending"
        );
        assertEq(dispute.createdAt, block.timestamp, "Created at should match");
        assertEq(dispute.stakeSnapshot, stakeSnapshot, "Stake snapshot should match");

        // Check that the fisherman was charged the dispute deposit
        uint256 afterFishermanBalance = token.balanceOf(fisherman);
        assertEq(
            afterFishermanBalance,
            beforeFishermanBalance - disputeDeposit,
            "Fisherman should be charged the dispute deposit"
        );

        return _disputeId;
    }

    function _createQueryDispute(bytes memory _attestationData) internal returns (bytes32) {
        (, address fisherman, ) = vm.readCallers();
        Attestation.State memory attestation = Attestation.parse(_attestationData);
        address indexer = disputeManager.getAttestationIndexer(attestation);
        bytes32 expectedDisputeId = keccak256(
            abi.encodePacked(
                attestation.requestCID,
                attestation.responseCID,
                attestation.subgraphDeploymentId,
                indexer,
                fisherman
            )
        );
        uint256 disputeDeposit = disputeManager.disputeDeposit();
        uint256 beforeFishermanBalance = token.balanceOf(fisherman);
        uint256 stakeSnapshot = disputeManager.getStakeSnapshot(indexer);

        // Approve the dispute deposit
        token.approve(address(disputeManager), disputeDeposit);

        vm.expectEmit(address(disputeManager));
        emit IDisputeManager.QueryDisputeCreated(
            expectedDisputeId,
            indexer,
            fisherman,
            disputeDeposit,
            attestation.subgraphDeploymentId,
            _attestationData,
            stakeSnapshot
        );

        bytes32 _disputeID = disputeManager.createQueryDispute(_attestationData);

        // Check that the dispute was created and that it has the correct ID
        assertTrue(disputeManager.isDisputeCreated(_disputeID), "Dispute should be created.");
        assertEq(expectedDisputeId, _disputeID, "Dispute ID should match");

        // Check dispute values
        IDisputeManager.Dispute memory dispute = _getDispute(_disputeID);
        assertEq(dispute.indexer, indexer, "Indexer should match");
        assertEq(dispute.fisherman, fisherman, "Fisherman should match");
        assertEq(dispute.deposit, disputeDeposit, "Deposit should match");
        assertEq(dispute.relatedDisputeId, bytes32(0), "Related dispute ID should be empty");
        assertEq(
            uint8(dispute.disputeType),
            uint8(IDisputeManager.DisputeType.QueryDispute),
            "Dispute type should be query"
        );
        assertEq(
            uint8(dispute.status),
            uint8(IDisputeManager.DisputeStatus.Pending),
            "Dispute status should be pending"
        );
        assertEq(dispute.createdAt, block.timestamp, "Created at should match");
        assertEq(dispute.stakeSnapshot, stakeSnapshot, "Stake snapshot should match");

        // Check that the fisherman was charged the dispute deposit
        uint256 afterFishermanBalance = token.balanceOf(fisherman);
        assertEq(
            afterFishermanBalance,
            beforeFishermanBalance - disputeDeposit,
            "Fisherman should be charged the dispute deposit"
        );

        return _disputeID;
    }

    struct Balances {
        uint256 indexer;
        uint256 fisherman;
        uint256 arbitrator;
        uint256 disputeManager;
        uint256 staking;
    }

    function _createAndAcceptLegacyDispute(
        address _allocationId,
        address _fisherman,
        uint256 _tokensSlash,
        uint256 _tokensRewards
    ) internal returns (bytes32) {
        (, address arbitrator, ) = vm.readCallers();
        address indexer = staking.getAllocation(_allocationId).indexer;

        Balances memory beforeBalances = Balances({
            indexer: token.balanceOf(indexer),
            fisherman: token.balanceOf(_fisherman),
            arbitrator: token.balanceOf(arbitrator),
            disputeManager: token.balanceOf(address(disputeManager)),
            staking: token.balanceOf(address(staking))
        });

        vm.expectEmit(address(disputeManager));
        emit IDisputeManager.LegacyDisputeCreated(
            keccak256(abi.encodePacked(_allocationId, "legacy")),
            indexer,
            _fisherman,
            _allocationId,
            _tokensSlash,
            _tokensRewards
        );
        vm.expectEmit(address(disputeManager));
        emit IDisputeManager.DisputeAccepted(
            keccak256(abi.encodePacked(_allocationId, "legacy")),
            indexer,
            _fisherman,
            _tokensRewards
        );
        bytes32 _disputeId = disputeManager.createAndAcceptLegacyDispute(
            _allocationId,
            _fisherman,
            _tokensSlash,
            _tokensRewards
        );

        Balances memory afterBalances = Balances({
            indexer: token.balanceOf(indexer),
            fisherman: token.balanceOf(_fisherman),
            arbitrator: token.balanceOf(arbitrator),
            disputeManager: token.balanceOf(address(disputeManager)),
            staking: token.balanceOf(address(staking))
        });

        assertEq(afterBalances.indexer, beforeBalances.indexer);
        assertEq(afterBalances.fisherman, beforeBalances.fisherman + _tokensRewards);
        assertEq(afterBalances.arbitrator, beforeBalances.arbitrator);
        assertEq(afterBalances.disputeManager, beforeBalances.disputeManager);
        assertEq(afterBalances.staking, beforeBalances.staking - _tokensSlash);

        IDisputeManager.Dispute memory dispute = _getDispute(_disputeId);
        assertEq(dispute.indexer, indexer);
        assertEq(dispute.fisherman, _fisherman);
        assertEq(dispute.deposit, 0);
        assertEq(dispute.relatedDisputeId, bytes32(0));
        assertEq(uint8(dispute.disputeType), uint8(IDisputeManager.DisputeType.LegacyDispute));
        assertEq(uint8(dispute.status), uint8(IDisputeManager.DisputeStatus.Accepted));
        assertEq(dispute.createdAt, block.timestamp);
        assertEq(dispute.stakeSnapshot, 0);

        return _disputeId;
    }

    struct BeforeValues_CreateQueryDisputeConflict {
        Attestation.State attestation1;
        Attestation.State attestation2;
        address indexer1;
        address indexer2;
        uint256 stakeSnapshot1;
        uint256 stakeSnapshot2;
    }

    function _createQueryDisputeConflict(
        bytes memory attestationData1,
        bytes memory attestationData2
    ) internal returns (bytes32, bytes32) {
        (, address fisherman, ) = vm.readCallers();

        BeforeValues_CreateQueryDisputeConflict memory beforeValues;
        beforeValues.attestation1 = Attestation.parse(attestationData1);
        beforeValues.attestation2 = Attestation.parse(attestationData2);
        beforeValues.indexer1 = disputeManager.getAttestationIndexer(beforeValues.attestation1);
        beforeValues.indexer2 = disputeManager.getAttestationIndexer(beforeValues.attestation2);
        beforeValues.stakeSnapshot1 = disputeManager.getStakeSnapshot(beforeValues.indexer1);
        beforeValues.stakeSnapshot2 = disputeManager.getStakeSnapshot(beforeValues.indexer2);

        uint256 beforeFishermanBalance = token.balanceOf(fisherman);

        // Approve the dispute deposit
        token.approve(address(disputeManager), disputeDeposit);

        bytes32 expectedDisputeId1 = keccak256(
            abi.encodePacked(
                beforeValues.attestation1.requestCID,
                beforeValues.attestation1.responseCID,
                beforeValues.attestation1.subgraphDeploymentId,
                beforeValues.indexer1,
                fisherman
            )
        );
        bytes32 expectedDisputeId2 = keccak256(
            abi.encodePacked(
                beforeValues.attestation2.requestCID,
                beforeValues.attestation2.responseCID,
                beforeValues.attestation2.subgraphDeploymentId,
                beforeValues.indexer2,
                fisherman
            )
        );

        // createQueryDisputeConflict
        vm.expectEmit(address(disputeManager));
        emit IDisputeManager.QueryDisputeCreated(
            expectedDisputeId1,
            beforeValues.indexer1,
            fisherman,
            disputeDeposit / 2,
            beforeValues.attestation1.subgraphDeploymentId,
            attestationData1,
            beforeValues.stakeSnapshot1
        );
        vm.expectEmit(address(disputeManager));
        emit IDisputeManager.QueryDisputeCreated(
            expectedDisputeId2,
            beforeValues.indexer2,
            fisherman,
            disputeDeposit / 2,
            beforeValues.attestation2.subgraphDeploymentId,
            attestationData2,
            beforeValues.stakeSnapshot2
        );

        (bytes32 _disputeId1, bytes32 _disputeId2) = disputeManager.createQueryDisputeConflict(
            attestationData1,
            attestationData2
        );

        // Check that the disputes were created and that they have the correct IDs
        assertTrue(disputeManager.isDisputeCreated(_disputeId1), "Dispute 1 should be created.");
        assertTrue(disputeManager.isDisputeCreated(_disputeId2), "Dispute 2 should be created.");
        assertEq(expectedDisputeId1, _disputeId1, "Dispute 1 ID should match");
        assertEq(expectedDisputeId2, _disputeId2, "Dispute 2 ID should match");

        // Check dispute values
        IDisputeManager.Dispute memory dispute1 = _getDispute(_disputeId1);
        assertEq(dispute1.indexer, beforeValues.indexer1, "Indexer 1 should match");
        assertEq(dispute1.fisherman, fisherman, "Fisherman 1 should match");
        assertEq(dispute1.deposit, disputeDeposit / 2, "Deposit 1 should match");
        assertEq(dispute1.relatedDisputeId, _disputeId2, "Related dispute ID 1 should be the id of the other dispute");
        assertEq(
            uint8(dispute1.disputeType),
            uint8(IDisputeManager.DisputeType.QueryDispute),
            "Dispute type 1 should be query"
        );
        assertEq(
            uint8(dispute1.status),
            uint8(IDisputeManager.DisputeStatus.Pending),
            "Dispute status 1 should be pending"
        );
        assertEq(dispute1.createdAt, block.timestamp, "Created at 1 should match");
        assertEq(dispute1.stakeSnapshot, beforeValues.stakeSnapshot1, "Stake snapshot 1 should match");

        IDisputeManager.Dispute memory dispute2 = _getDispute(_disputeId2);
        assertEq(dispute2.indexer, beforeValues.indexer2, "Indexer 2 should match");
        assertEq(dispute2.fisherman, fisherman, "Fisherman 2 should match");
        assertEq(dispute2.deposit, disputeDeposit / 2, "Deposit 2 should match");
        assertEq(dispute2.relatedDisputeId, _disputeId1, "Related dispute ID 2 should be the id of the other dispute");
        assertEq(
            uint8(dispute2.disputeType),
            uint8(IDisputeManager.DisputeType.QueryDispute),
            "Dispute type 2 should be query"
        );
        assertEq(
            uint8(dispute2.status),
            uint8(IDisputeManager.DisputeStatus.Pending),
            "Dispute status 2 should be pending"
        );
        assertEq(dispute2.createdAt, block.timestamp, "Created at 2 should match");
        assertEq(dispute2.stakeSnapshot, beforeValues.stakeSnapshot2, "Stake snapshot 2 should match");

        // Check that the fisherman was charged the dispute deposit
        uint256 afterFishermanBalance = token.balanceOf(fisherman);
        assertEq(
            afterFishermanBalance,
            beforeFishermanBalance - disputeDeposit,
            "Fisherman should be charged the dispute deposit"
        );

        return (_disputeId1, _disputeId2);
    }

    function _acceptDispute(bytes32 _disputeId, uint256 _tokensSlash) internal {
        IDisputeManager.Dispute memory dispute = _getDispute(_disputeId);
        address fisherman = dispute.fisherman;
        uint256 fishermanPreviousBalance = token.balanceOf(fisherman);
        uint256 indexerTokensAvailable = staking.getProviderTokensAvailable(dispute.indexer, address(subgraphService));
        uint256 disputeDeposit = dispute.deposit;
        uint256 fishermanRewardPercentage = disputeManager.fishermanRewardCut();
        uint256 fishermanReward = _tokensSlash.mulPPM(fishermanRewardPercentage);

        vm.expectEmit(address(disputeManager));
        emit IDisputeManager.DisputeAccepted(
            _disputeId,
            dispute.indexer,
            dispute.fisherman,
            dispute.deposit + fishermanReward
        );

        // Accept the dispute
        disputeManager.acceptDispute(_disputeId, _tokensSlash);

        // Check fisherman's got their reward and their deposit (if any) back
        uint256 fishermanExpectedBalance = fishermanPreviousBalance + fishermanReward + disputeDeposit;
        assertEq(
            token.balanceOf(fisherman),
            fishermanExpectedBalance,
            "Fisherman should get their reward and deposit back"
        );

        // Check indexer was slashed by the correct amount
        uint256 expectedIndexerTokensAvailable;
        if (_tokensSlash > indexerTokensAvailable) {
            expectedIndexerTokensAvailable = 0;
        } else {
            expectedIndexerTokensAvailable = indexerTokensAvailable - _tokensSlash;
        }
        assertEq(
            staking.getProviderTokensAvailable(dispute.indexer, address(subgraphService)),
            expectedIndexerTokensAvailable,
            "Indexer should be slashed by the correct amount"
        );

        // Check dispute status
        dispute = _getDispute(_disputeId);
        assertEq(
            uint8(dispute.status),
            uint8(IDisputeManager.DisputeStatus.Accepted),
            "Dispute status should be accepted"
        );
    }

    struct FishermanParams {
        address fisherman;
        uint256 previousBalance;
        uint256 disputeDeposit;
        uint256 relatedDisputeDeposit;
        uint256 rewardPercentage;
        uint256 rewardFirstDispute;
        uint256 rewardRelatedDispute;
        uint256 totalReward;
        uint256 expectedBalance;
    }

    function _acceptDisputeConflict(
        bytes32 _disputeId,
        uint256 _tokensSlash,
        bool _acceptRelatedDispute,
        uint256 _tokensRelatedSlash
    ) internal {
        IDisputeManager.Dispute memory dispute = _getDispute(_disputeId);
        IDisputeManager.Dispute memory relatedDispute = _getDispute(dispute.relatedDisputeId);
        uint256 indexerTokensAvailable = staking.getProviderTokensAvailable(dispute.indexer, address(subgraphService));
        uint256 relatedIndexerTokensAvailable = staking.getProviderTokensAvailable(
            relatedDispute.indexer,
            address(subgraphService)
        );

        FishermanParams memory params;
        params.fisherman = dispute.fisherman;
        params.previousBalance = token.balanceOf(params.fisherman);
        params.disputeDeposit = dispute.deposit;
        params.relatedDisputeDeposit = relatedDispute.deposit;
        params.rewardPercentage = disputeManager.fishermanRewardCut();
        params.rewardFirstDispute = _tokensSlash.mulPPM(params.rewardPercentage);
        params.rewardRelatedDispute = (_acceptRelatedDispute) ? _tokensRelatedSlash.mulPPM(params.rewardPercentage) : 0;
        params.totalReward = params.rewardFirstDispute + params.rewardRelatedDispute;

        vm.expectEmit(address(disputeManager));
        emit IDisputeManager.DisputeAccepted(
            _disputeId,
            dispute.indexer,
            params.fisherman,
            params.disputeDeposit + params.rewardFirstDispute
        );

        if (_acceptRelatedDispute) {
            emit IDisputeManager.DisputeAccepted(
                dispute.relatedDisputeId,
                relatedDispute.indexer,
                relatedDispute.fisherman,
                relatedDispute.deposit + params.rewardRelatedDispute
            );
        } else {
            emit IDisputeManager.DisputeDrawn(
                dispute.relatedDisputeId,
                relatedDispute.indexer,
                relatedDispute.fisherman,
                relatedDispute.deposit
            );
        }

        // Accept the dispute
        disputeManager.acceptDisputeConflict(_disputeId, _tokensSlash, _acceptRelatedDispute, _tokensRelatedSlash);

        // Check fisherman's got their reward and their deposit back
        params.expectedBalance =
            params.previousBalance +
            params.totalReward +
            params.disputeDeposit +
            params.relatedDisputeDeposit;
        assertEq(
            token.balanceOf(params.fisherman),
            params.expectedBalance,
            "Fisherman should get their reward and deposit back"
        );

        // If both disputes are for the same indexer, check that the indexer was slashed by the correct amount
        if (dispute.indexer == relatedDispute.indexer) {
            uint256 tokensToSlash = (_acceptRelatedDispute) ? _tokensSlash + _tokensRelatedSlash : _tokensSlash;
            uint256 expectedIndexerTokensAvailable;
            if (tokensToSlash > indexerTokensAvailable) {
                expectedIndexerTokensAvailable = 0;
            } else {
                expectedIndexerTokensAvailable = indexerTokensAvailable - tokensToSlash;
            }
            assertEq(
                staking.getProviderTokensAvailable(dispute.indexer, address(subgraphService)),
                expectedIndexerTokensAvailable,
                "Indexer should be slashed by the correct amount"
            );
        } else {
            // Check indexer for first dispute was slashed by the correct amount
            uint256 expectedIndexerTokensAvailable;
            uint256 tokensToSlash = (_acceptRelatedDispute) ? _tokensSlash : _tokensSlash;
            if (tokensToSlash > indexerTokensAvailable) {
                expectedIndexerTokensAvailable = 0;
            } else {
                expectedIndexerTokensAvailable = indexerTokensAvailable - tokensToSlash;
            }
            assertEq(
                staking.getProviderTokensAvailable(dispute.indexer, address(subgraphService)),
                expectedIndexerTokensAvailable,
                "Indexer should be slashed by the correct amount"
            );

            // Check indexer for related dispute was slashed by the correct amount if it was accepted
            if (_acceptRelatedDispute) {
                uint256 expectedRelatedIndexerTokensAvailable;
                if (_tokensRelatedSlash > relatedIndexerTokensAvailable) {
                    expectedRelatedIndexerTokensAvailable = 0;
                } else {
                    expectedRelatedIndexerTokensAvailable = relatedIndexerTokensAvailable - _tokensRelatedSlash;
                }
                assertEq(
                    staking.getProviderTokensAvailable(relatedDispute.indexer, address(subgraphService)),
                    expectedRelatedIndexerTokensAvailable,
                    "Indexer should be slashed by the correct amount"
                );
            }
        }

        // Check dispute status
        dispute = _getDispute(_disputeId);
        assertEq(
            uint8(dispute.status),
            uint8(IDisputeManager.DisputeStatus.Accepted),
            "Dispute status should be accepted"
        );

        // If there's a related dispute, check it
        relatedDispute = _getDispute(dispute.relatedDisputeId);
        assertEq(
            uint8(relatedDispute.status),
            _acceptRelatedDispute
                ? uint8(IDisputeManager.DisputeStatus.Accepted)
                : uint8(IDisputeManager.DisputeStatus.Drawn),
            "Related dispute status should be drawn"
        );
    }

    function _drawDispute(bytes32 _disputeId) internal {
        IDisputeManager.Dispute memory dispute = _getDispute(_disputeId);
        bool isConflictingDispute = dispute.relatedDisputeId != bytes32(0);
        IDisputeManager.Dispute memory relatedDispute;
        if (isConflictingDispute) relatedDispute = _getDispute(dispute.relatedDisputeId);
        address fisherman = dispute.fisherman;
        uint256 fishermanPreviousBalance = token.balanceOf(fisherman);
        uint256 indexerTokensAvailable = staking.getProviderTokensAvailable(dispute.indexer, address(subgraphService));

        vm.expectEmit(address(disputeManager));
        emit IDisputeManager.DisputeDrawn(_disputeId, dispute.indexer, dispute.fisherman, dispute.deposit);

        if (isConflictingDispute) {
            emit IDisputeManager.DisputeDrawn(
                dispute.relatedDisputeId,
                relatedDispute.indexer,
                relatedDispute.fisherman,
                relatedDispute.deposit
            );
        }
        // Draw the dispute
        disputeManager.drawDispute(_disputeId);

        // Check that the fisherman got their deposit back
        uint256 fishermanExpectedBalance = fishermanPreviousBalance +
            dispute.deposit +
            (isConflictingDispute ? relatedDispute.deposit : 0);
        assertEq(token.balanceOf(fisherman), fishermanExpectedBalance, "Fisherman should receive their deposit back.");

        // Check that indexer was not slashed
        assertEq(
            staking.getProviderTokensAvailable(dispute.indexer, address(subgraphService)),
            indexerTokensAvailable,
            "Indexer should not be slashed"
        );

        // Check dispute status
        dispute = _getDispute(_disputeId);
        assertEq(uint8(dispute.status), uint8(IDisputeManager.DisputeStatus.Drawn), "Dispute status should be drawn");

        // If there's a related dispute, check that it was drawn too
        if (dispute.relatedDisputeId != bytes32(0)) {
            relatedDispute = _getDispute(dispute.relatedDisputeId);
            assertEq(
                uint8(relatedDispute.status),
                uint8(IDisputeManager.DisputeStatus.Drawn),
                "Related dispute status should be drawn"
            );
        }
    }

    function _rejectDispute(bytes32 _disputeId) internal {
        IDisputeManager.Dispute memory dispute = _getDispute(_disputeId);
        address fisherman = dispute.fisherman;
        uint256 fishermanPreviousBalance = token.balanceOf(fisherman);
        uint256 indexerTokensAvailable = staking.getProviderTokensAvailable(dispute.indexer, address(subgraphService));

        vm.expectEmit(address(disputeManager));
        emit IDisputeManager.DisputeRejected(_disputeId, dispute.indexer, dispute.fisherman, dispute.deposit);

        // Reject the dispute
        disputeManager.rejectDispute(_disputeId);

        // Check that the fisherman didn't get their deposit back
        assertEq(token.balanceOf(users.fisherman), fishermanPreviousBalance, "Fisherman should lose the deposit.");

        // Check that indexer was not slashed
        assertEq(
            staking.getProviderTokensAvailable(dispute.indexer, address(subgraphService)),
            indexerTokensAvailable,
            "Indexer should not be slashed"
        );

        // Check dispute status
        dispute = _getDispute(_disputeId);
        assertEq(
            uint8(dispute.status),
            uint8(IDisputeManager.DisputeStatus.Rejected),
            "Dispute status should be rejected"
        );
        // Checl related id is empty
        assertEq(dispute.relatedDisputeId, bytes32(0), "Related dispute ID should be empty");
    }

    function _cancelDispute(bytes32 _disputeId) internal {
        IDisputeManager.Dispute memory dispute = _getDispute(_disputeId);
        bool isDisputeInConflict = dispute.relatedDisputeId != bytes32(0);
        IDisputeManager.Dispute memory relatedDispute;
        if (isDisputeInConflict) relatedDispute = _getDispute(dispute.relatedDisputeId);
        address fisherman = dispute.fisherman;
        uint256 fishermanPreviousBalance = token.balanceOf(fisherman);
        uint256 disputePeriod = disputeManager.disputePeriod();
        uint256 indexerTokensAvailable = staking.getProviderTokensAvailable(dispute.indexer, address(subgraphService));

        // skip to end of dispute period
        skip(disputePeriod + 1);

        vm.expectEmit(address(disputeManager));
        emit IDisputeManager.DisputeCancelled(_disputeId, dispute.indexer, dispute.fisherman, dispute.deposit);

        if (isDisputeInConflict) {
            emit IDisputeManager.DisputeCancelled(
                dispute.relatedDisputeId,
                relatedDispute.indexer,
                relatedDispute.fisherman,
                relatedDispute.deposit
            );
        }

        // Cancel the dispute
        disputeManager.cancelDispute(_disputeId);

        // Check that the fisherman got their deposit back
        uint256 fishermanExpectedBalance = fishermanPreviousBalance +
            dispute.deposit +
            (isDisputeInConflict ? relatedDispute.deposit : 0);
        assertEq(
            token.balanceOf(users.fisherman),
            fishermanExpectedBalance,
            "Fisherman should receive their deposit back."
        );

        // Check that indexer was not slashed
        assertEq(
            staking.getProviderTokensAvailable(dispute.indexer, address(subgraphService)),
            indexerTokensAvailable,
            "Indexer should not be slashed"
        );

        // Check dispute status
        dispute = _getDispute(_disputeId);
        assertEq(
            uint8(dispute.status),
            uint8(IDisputeManager.DisputeStatus.Cancelled),
            "Dispute status should be cancelled"
        );

        if (isDisputeInConflict) {
            relatedDispute = _getDispute(dispute.relatedDisputeId);
            assertEq(
                uint8(relatedDispute.status),
                uint8(IDisputeManager.DisputeStatus.Cancelled),
                "Related dispute status should be cancelled"
            );
        }
    }

    /*
     * HELPERS
     */

    function _createAttestationReceipt(
        bytes32 requestCID,
        bytes32 responseCID,
        bytes32 subgraphDeploymentId
    ) internal pure returns (Attestation.Receipt memory receipt) {
        return
            Attestation.Receipt({
                requestCID: requestCID,
                responseCID: responseCID,
                subgraphDeploymentId: subgraphDeploymentId
            });
    }

    function _createConflictingAttestations(
        bytes32 requestCID,
        bytes32 subgraphDeploymentId,
        bytes32 responseCID1,
        bytes32 responseCID2,
        uint256 signer1,
        uint256 signer2
    ) internal view returns (bytes memory attestationData1, bytes memory attestationData2) {
        Attestation.Receipt memory receipt1 = _createAttestationReceipt(requestCID, responseCID1, subgraphDeploymentId);
        Attestation.Receipt memory receipt2 = _createAttestationReceipt(requestCID, responseCID2, subgraphDeploymentId);

        bytes memory _attestationData1 = _createAtestationData(receipt1, signer1);
        bytes memory _attestationData2 = _createAtestationData(receipt2, signer2);
        return (_attestationData1, _attestationData2);
    }

    function _createAtestationData(
        Attestation.Receipt memory receipt,
        uint256 signer
    ) internal view returns (bytes memory attestationData) {
        bytes32 digest = disputeManager.encodeReceipt(receipt);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, digest);

        return abi.encodePacked(receipt.requestCID, receipt.responseCID, receipt.subgraphDeploymentId, r, s, v);
    }

    /*
     * PRIVATE FUNCTIONS
     */

    function _getDispute(bytes32 _disputeId) internal view returns (IDisputeManager.Dispute memory) {
        (
            address indexer,
            address fisherman,
            uint256 deposit,
            bytes32 relatedDisputeId,
            IDisputeManager.DisputeType disputeType,
            IDisputeManager.DisputeStatus status,
            uint256 createdAt,
            uint256 stakeSnapshot
        ) = disputeManager.disputes(_disputeId);
        return
            IDisputeManager.Dispute({
                indexer: indexer,
                fisherman: fisherman,
                deposit: deposit,
                relatedDisputeId: relatedDisputeId,
                disputeType: disputeType,
                status: status,
                createdAt: createdAt,
                stakeSnapshot: stakeSnapshot
            });
    }

    function _setStorage_SubgraphService(address _subgraphService) internal {
        vm.store(address(disputeManager), bytes32(uint256(51)), bytes32(uint256(uint160(_subgraphService))));
    }
}
