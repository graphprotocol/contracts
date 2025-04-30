// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { Attestation } from "../../../../contracts/libraries/Attestation.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryAcceptDisputeTest is DisputeManagerTest {
    using PPMMath for uint256;

    bytes32 private requestCID = keccak256(abi.encodePacked("Request CID"));
    bytes32 private responseCID = keccak256(abi.encodePacked("Response CID"));
    bytes32 private subgraphDeploymentId = keccak256(abi.encodePacked("Subgraph Deployment ID"));

    /*
     * TESTS
     */

    function test_Query_Accept_Dispute(uint256 tokens, uint256 tokensSlash) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        resetPrank(users.arbitrator);
        _acceptDispute(disputeID, tokensSlash);
    }

    function test_Query_Accept_Dispute_RevertWhen_SubgraphServiceNotSet(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        resetPrank(users.arbitrator);
        // clear subgraph service address from storage
        _setStorage_SubgraphService(address(0));
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerSubgraphServiceNotSet.selector));
        disputeManager.acceptDispute(disputeID, tokensSlash);
    }

    function test_Query_Accept_Dispute_OptParam(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        resetPrank(users.arbitrator);
        _acceptDispute(disputeID, tokensSlash);
    }

    function test_Query_Accept_RevertIf_CallerIsNotArbitrator(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        // attempt to accept dispute as fisherman
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.acceptDispute(disputeID, tokensSlash);
    }

    function test_Query_Accept_RevertWhen_SlashingOverMaxSlashPercentage(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, uint256(maxSlashingPercentage).mulPPM(tokens) + 1, type(uint256).max);

        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        // max slashing percentage is 50%
        resetPrank(users.arbitrator);
        uint256 maxTokensToSlash = uint256(maxSlashingPercentage).mulPPM(tokens);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidTokensSlash.selector,
            tokensSlash,
            maxTokensToSlash
        );
        vm.expectRevert(expectedError);
        disputeManager.acceptDispute(disputeID, tokensSlash);
    }

    function test_Query_Accept_RevertWhen_UsingConflictAccept(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputeNotInConflict.selector, disputeID));
        disputeManager.acceptDisputeConflict(disputeID, tokensSlash, true, 0);
    }

    function test_Query_Accept_RevertWhen_SlashingOverMaxSlashPercentage_WithDelegation(
        uint256 tokens,
        uint256 tokensDelegated,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) useDelegation(tokensDelegated) {
        uint256 maxTokensToSlash = uint256(maxSlashingPercentage).mulPPM(
            _calculateStakeSnapshot(tokens, tokensDelegated)
        );
        tokensSlash = bound(tokensSlash, maxTokensToSlash + 1, type(uint256).max);

        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        // max slashing percentage is 50%
        resetPrank(users.arbitrator);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidTokensSlash.selector,
            tokensSlash,
            maxTokensToSlash
        );
        vm.expectRevert(expectedError);
        disputeManager.acceptDispute(disputeID, tokensSlash);
    }


    function test_Query_Accept_RevertWhen_SlashingOverMaxSlashPercentage_WithDelegation_DelegationSlashing(
        uint256 tokens,
        uint256 tokensDelegated,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) useDelegation(tokensDelegated) {
        // enable delegation slashing
        resetPrank(users.governor);
        staking.setDelegationSlashingEnabled();

        resetPrank(users.fisherman);
        uint256 maxTokensToSlash = uint256(maxSlashingPercentage).mulPPM(
            _calculateStakeSnapshot(tokens, tokensDelegated)
        );
        tokensSlash = bound(tokensSlash, maxTokensToSlash + 1, type(uint256).max);

        // Create a new dispute with delegation slashing enabled
        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        // max slashing percentage is 50%
        resetPrank(users.arbitrator);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidTokensSlash.selector,
            tokensSlash,
            maxTokensToSlash
        );
        vm.expectRevert(expectedError);
        disputeManager.acceptDispute(disputeID, tokensSlash);
    }

    function test_Query_Accept_Dispute_AfterFishermanRewardCutIncreased(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer {
        vm.assume(tokens >= minimumProvisionTokens);
        vm.assume(tokens < 10_000_000_000 ether);
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

        // Set fishermanRewardCut to 25%
        resetPrank(users.governor);
        uint32 oldFishermanRewardCut = 250_000;
        disputeManager.setFishermanRewardCut(oldFishermanRewardCut);

        // Create provision with maxVerifierCut == fishermanRewardCut and allocate
        resetPrank(users.indexer);
        _createProvision(users.indexer, tokens, oldFishermanRewardCut, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));
        bytes memory data = _createSubgraphAllocationData(
            users.indexer,
            subgraphDeployment,
            allocationIDPrivateKey,
            tokens
        );
        _startService(users.indexer, data);

        // Create a dispute with prov.maxVerifierCut == fishermanRewardCut
        uint256 beforeFishermanBalance = token.balanceOf(users.fisherman);
        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        // Now bump the fishermanRewardCut to 50%
        resetPrank(users.governor);
        disputeManager.setFishermanRewardCut(500_000);

        // Accept the dispute
        resetPrank(users.arbitrator);
        _acceptDispute(disputeID, tokensSlash);

        // Check that the fisherman received the correct amount of tokens
        // which should use the old fishermanRewardCut
        uint256 afterFishermanBalance = token.balanceOf(users.fisherman);
        assertEq(afterFishermanBalance, beforeFishermanBalance + tokensSlash.mulPPM(oldFishermanRewardCut));
    }
}
