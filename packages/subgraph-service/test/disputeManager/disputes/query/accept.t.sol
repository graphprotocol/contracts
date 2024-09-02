// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

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

    function test_Query_Accept_Dispute(
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
}
