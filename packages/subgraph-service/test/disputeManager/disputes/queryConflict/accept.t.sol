// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryConflictAcceptDisputeTest is DisputeManagerTest {
    using PPMMath for uint256;

    bytes32 private requestCID = keccak256(abi.encodePacked("Request CID"));
    bytes32 private responseCID1 = keccak256(abi.encodePacked("Response CID 1"));
    bytes32 private responseCID2 = keccak256(abi.encodePacked("Response CID 2"));

    /*
     * TESTS
     */

    function test_Query_Conflict_Accept_Dispute_Draw_Other(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestCID,
            subgraphDeployment,
            responseCID1,
            responseCID2,
            allocationIDPrivateKey,
            allocationIDPrivateKey
        );

        uint256 fishermanBalanceBefore = token.balanceOf(users.fisherman);

        resetPrank(users.fisherman);
        (bytes32 disputeID1, ) = _createQueryDisputeConflict(attestationData1, attestationData2);

        resetPrank(users.arbitrator);
        _acceptDisputeConflict(disputeID1, tokensSlash, false, 0);

        uint256 fishermanRewardPercentage = disputeManager.fishermanRewardCut();
        uint256 fishermanReward = tokensSlash.mulPPM(fishermanRewardPercentage);
        uint256 fishermanBalanceAfter = token.balanceOf(users.fisherman);

        assertEq(fishermanBalanceAfter, fishermanBalanceBefore + fishermanReward);
    }

    function test_Query_Conflict_Accept_Dispute_Accept_Other(
        uint256 tokens,
        uint256 tokensSlash,
        uint256 tokensSlashRelatedDispute
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));
        tokensSlashRelatedDispute = bound(tokensSlashRelatedDispute, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestCID,
            subgraphDeployment,
            responseCID1,
            responseCID2,
            allocationIDPrivateKey,
            allocationIDPrivateKey
        );

        uint256 fishermanBalanceBefore = token.balanceOf(users.fisherman);

        resetPrank(users.fisherman);
        (bytes32 disputeID1, ) = _createQueryDisputeConflict(attestationData1, attestationData2);

        resetPrank(users.arbitrator);
        _acceptDisputeConflict(disputeID1, tokensSlash, true, tokensSlashRelatedDispute);

        uint256 fishermanRewardPercentage = disputeManager.fishermanRewardCut();
        uint256 fishermanRewardFirstDispute = tokensSlash.mulPPM(fishermanRewardPercentage);
        uint256 fishermanRewardRelatedDispute = tokensSlashRelatedDispute.mulPPM(fishermanRewardPercentage);
        uint256 fishermanReward = fishermanRewardFirstDispute + fishermanRewardRelatedDispute;
        uint256 fishermanBalanceAfter = token.balanceOf(users.fisherman);

        assertEq(fishermanBalanceAfter, fishermanBalanceBefore + fishermanReward);
    }

    function test_Query_Conflict_Accept_RevertIf_CallerIsNotArbitrator(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestCID,
            subgraphDeployment,
            responseCID1,
            responseCID2,
            allocationIDPrivateKey,
            allocationIDPrivateKey
        );

        resetPrank(users.fisherman);
        (bytes32 disputeID1, ) = _createQueryDisputeConflict(attestationData1, attestationData2);

        // attempt to accept dispute as fisherman
        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.acceptDisputeConflict(disputeID1, tokensSlash, false, 0);
    }

    function test_Query_Conflict_Accept_RevertWhen_SlashingOverMaxSlashPercentage(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, uint256(maxSlashingPercentage).mulPPM(tokens) + 1, type(uint256).max);

        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestCID,
            subgraphDeployment,
            responseCID1,
            responseCID2,
            allocationIDPrivateKey,
            allocationIDPrivateKey
        );

        resetPrank(users.fisherman);
        (bytes32 disputeID1, ) = _createQueryDisputeConflict(attestationData1, attestationData2);

        // max slashing percentage is 50%
        resetPrank(users.arbitrator);
        uint256 maxTokensToSlash = uint256(maxSlashingPercentage).mulPPM(tokens);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidTokensSlash.selector,
            tokensSlash,
            maxTokensToSlash
        );
        vm.expectRevert(expectedError);
        disputeManager.acceptDisputeConflict(disputeID1, tokensSlash, false, 0);
    }

    function test_Query_Conflict_Accept_AcceptRelated_DifferentIndexer(
        uint256 tokensFirstIndexer,
        uint256 tokensSecondIndexer,
        uint256 tokensSlash,
        uint256 tokensSlashRelatedDispute
    ) public useIndexer useAllocation(tokensFirstIndexer) {
        tokensSecondIndexer = bound(tokensSecondIndexer, minimumProvisionTokens, 10_000_000_000 ether);
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokensFirstIndexer));

        // Setup different indexer for related dispute
        address differentIndexer = makeAddr("DifferentIndexer");
        mint(differentIndexer, tokensSecondIndexer);
        uint256 differentIndexerAllocationIDPrivateKey = uint256(keccak256(abi.encodePacked(differentIndexer)));
        resetPrank(differentIndexer);
        _createProvision(differentIndexer, tokensSecondIndexer, fishermanRewardPercentage, disputePeriod);
        _register(differentIndexer, abi.encode("url", "geoHash", address(0)));
        bytes memory data = _createSubgraphAllocationData(
            differentIndexer,
            subgraphDeployment,
            differentIndexerAllocationIDPrivateKey,
            tokensSecondIndexer
        );
        _startService(differentIndexer, data);
        tokensSlashRelatedDispute = bound(
            tokensSlashRelatedDispute,
            1,
            uint256(maxSlashingPercentage).mulPPM(tokensSecondIndexer)
        );

        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestCID,
            subgraphDeployment,
            responseCID1,
            responseCID2,
            allocationIDPrivateKey,
            differentIndexerAllocationIDPrivateKey
        );

        resetPrank(users.fisherman);
        (bytes32 disputeID1, ) = _createQueryDisputeConflict(attestationData1, attestationData2);

        resetPrank(users.arbitrator);
        _acceptDisputeConflict(disputeID1, tokensSlash, true, tokensSlashRelatedDispute);
    }

    function test_Query_Conflict_Accept_RevertWhen_UsingSingleAccept(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

        (bytes memory attestationData1, bytes memory attestationData2) = _createConflictingAttestations(
            requestCID,
            subgraphDeployment,
            responseCID1,
            responseCID2,
            allocationIDPrivateKey,
            allocationIDPrivateKey
        );

        resetPrank(users.fisherman);
        (bytes32 disputeID1, ) = _createQueryDisputeConflict(attestationData1, attestationData2);

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputeInConflict.selector, disputeID1));
        disputeManager.acceptDispute(disputeID1, tokensSlash);
    }
}
