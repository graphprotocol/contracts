// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IAttestation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAttestation.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "@graphprotocol/interfaces/contracts/subgraph-service/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryAcceptDisputeTest is DisputeManagerTest {
    using PPMMath for uint256;

    bytes32 private requestCid = keccak256(abi.encodePacked("Request CID"));
    bytes32 private responseCid = keccak256(abi.encodePacked("Response CID"));
    bytes32 private subgraphDeploymentId = keccak256(abi.encodePacked("Subgraph Deployment ID"));

    /*
     * TESTS
     */

    function test_Query_Accept_Dispute(uint256 tokens, uint256 tokensSlash) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens));

        resetPrank(users.fisherman);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        bytes32 disputeId = _createQueryDispute(attestationData);

        resetPrank(users.arbitrator);
        _acceptDispute(disputeId, tokensSlash);
    }

    function test_Query_Accept_Dispute_RevertWhen_SubgraphServiceNotSet(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens));

        resetPrank(users.fisherman);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        bytes32 disputeId = _createQueryDispute(attestationData);

        resetPrank(users.arbitrator);
        // clear subgraph service address from storage
        _setStorageSubgraphService(address(0));
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerSubgraphServiceNotSet.selector));
        disputeManager.acceptDispute(disputeId, tokensSlash);
    }

    function test_Query_Accept_Dispute_OptParam(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens));

        resetPrank(users.fisherman);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        bytes32 disputeId = _createQueryDispute(attestationData);

        resetPrank(users.arbitrator);
        _acceptDispute(disputeId, tokensSlash);
    }

    function test_Query_Accept_RevertIf_CallerIsNotArbitrator(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens));

        resetPrank(users.fisherman);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        bytes32 disputeId = _createQueryDispute(attestationData);

        // attempt to accept dispute as fisherman
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.acceptDispute(disputeId, tokensSlash);
    }

    function test_Query_Accept_RevertWhen_SlashingOverMaxSlashPercentage(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens) + 1, type(uint256).max);

        resetPrank(users.fisherman);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        bytes32 disputeId = _createQueryDispute(attestationData);

        // max slashing percentage is 50%
        resetPrank(users.arbitrator);
        uint256 maxTokensToSlash = uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidTokensSlash.selector,
            tokensSlash,
            maxTokensToSlash
        );
        vm.expectRevert(expectedError);
        disputeManager.acceptDispute(disputeId, tokensSlash);
    }

    function test_Query_Accept_RevertWhen_UsingConflictAccept(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens));

        resetPrank(users.fisherman);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        bytes32 disputeId = _createQueryDispute(attestationData);

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputeNotInConflict.selector, disputeId));
        disputeManager.acceptDisputeConflict(disputeId, tokensSlash, true, 0);
    }

    function test_Query_Accept_RevertWhen_SlashingOverMaxSlashPercentage_WithDelegation(
        uint256 tokens,
        uint256 tokensDelegated,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) useDelegation(tokensDelegated) {
        uint256 maxTokensToSlash = uint256(MAX_SLASHING_PERCENTAGE).mulPPM(
            _calculateStakeSnapshot(tokens, tokensDelegated)
        );
        tokensSlash = bound(tokensSlash, maxTokensToSlash + 1, type(uint256).max);

        resetPrank(users.fisherman);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        bytes32 disputeId = _createQueryDispute(attestationData);

        // max slashing percentage is 50%
        resetPrank(users.arbitrator);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidTokensSlash.selector,
            tokensSlash,
            maxTokensToSlash
        );
        vm.expectRevert(expectedError);
        disputeManager.acceptDispute(disputeId, tokensSlash);
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
        uint256 maxTokensToSlash = uint256(MAX_SLASHING_PERCENTAGE).mulPPM(
            _calculateStakeSnapshot(tokens, tokensDelegated)
        );
        tokensSlash = bound(tokensSlash, maxTokensToSlash + 1, type(uint256).max);

        // Create a new dispute with delegation slashing enabled
        resetPrank(users.fisherman);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        bytes32 disputeId = _createQueryDispute(attestationData);

        // max slashing percentage is 50%
        resetPrank(users.arbitrator);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidTokensSlash.selector,
            tokensSlash,
            maxTokensToSlash
        );
        vm.expectRevert(expectedError);
        disputeManager.acceptDispute(disputeId, tokensSlash);
    }

    function test_Query_Accept_Dispute_AfterFishermanRewardCutIncreased(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer {
        vm.assume(tokens >= MINIMUM_PROVISION_TOKENS);
        vm.assume(tokens < 10_000_000_000 ether);
        tokensSlash = bound(tokensSlash, 1, uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens));

        // Set fishermanRewardCut to 25%
        resetPrank(users.governor);
        uint32 oldFishermanRewardCut = 250_000;
        disputeManager.setFishermanRewardCut(oldFishermanRewardCut);

        // Create provision with maxVerifierCut == fishermanRewardCut and allocate
        resetPrank(users.indexer);
        _createProvision(users.indexer, tokens, oldFishermanRewardCut, DISPUTE_PERIOD);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));
        bytes memory data = _createSubgraphAllocationData(
            users.indexer,
            subgraphDeployment,
            allocationIdPrivateKey,
            tokens
        );
        _startService(users.indexer, data);

        // Create a dispute with prov.maxVerifierCut == fishermanRewardCut
        uint256 beforeFishermanBalance = token.balanceOf(users.fisherman);
        resetPrank(users.fisherman);
        IAttestation.Receipt memory receipt = _createAttestationReceipt(requestCid, responseCid, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIdPrivateKey);
        bytes32 disputeId = _createQueryDispute(attestationData);

        // Now bump the fishermanRewardCut to 50%
        resetPrank(users.governor);
        disputeManager.setFishermanRewardCut(500_000);

        // Accept the dispute
        resetPrank(users.arbitrator);
        _acceptDispute(disputeId, tokensSlash);

        // Check that the fisherman received the correct amount of tokens
        // which should use the old fishermanRewardCut (capped by provision's maxVerifierCut)
        uint256 afterFishermanBalance = token.balanceOf(users.fisherman);
        assertEq(afterFishermanBalance, beforeFishermanBalance + tokensSlash.mulPPM(oldFishermanRewardCut));
    }
}
