// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "../../contracts/interfaces/IDisputeManager.sol";
import { Attestation } from "../../contracts/libraries/Attestation.sol";

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

    modifier useFisherman {
        vm.startPrank(users.fisherman);
        _;
        vm.stopPrank();
    }

    /*
     * HELPERS
     */

    function _createIndexingDispute(address _allocationID, bytes32 _poi) internal returns (bytes32 disputeID) {
        address msgSender;
        (, msgSender,) = vm.readCallers();
        resetPrank(users.fisherman);
        uint256 beforeFishermanBalance = token.balanceOf(users.fisherman);
        token.approve(address(disputeManager), disputeDeposit);
        bytes32 _disputeID = disputeManager.createIndexingDispute(_allocationID, _poi);
        uint256 afterFishermanBalance = token.balanceOf(users.fisherman);
        assertEq(afterFishermanBalance, beforeFishermanBalance - disputeDeposit, "Fisherman should be charged the dispute deposit");
        resetPrank(msgSender);
        return _disputeID;
    }

    function _createQueryDispute() internal returns (bytes32 disputeID) {
        address msgSender;
        (, msgSender,) = vm.readCallers();
        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = Attestation.Receipt({
            requestCID: keccak256(abi.encodePacked("Request CID")),
            responseCID: keccak256(abi.encodePacked("Response CID")),
            subgraphDeploymentId: keccak256(abi.encodePacked("Subgraph Deployment ID"))
        });
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);

        uint256 beforeFishermanBalance = token.balanceOf(users.fisherman);
        token.approve(address(disputeManager), disputeDeposit);
        bytes32 _disputeID = disputeManager.createQueryDispute(attestationData);
        uint256 afterFishermanBalance = token.balanceOf(users.fisherman);
        assertEq(afterFishermanBalance, beforeFishermanBalance - disputeDeposit, "Fisherman should be charged the dispute deposit");
        resetPrank(msgSender);
        return _disputeID;
    }

    function _createConflictingAttestations(
        bytes32 responseCID1,
        bytes32 subgraphDeploymentId1,
        bytes32 responseCID2,
        bytes32 subgraphDeploymentId2
    ) internal view returns (bytes memory attestationData1, bytes memory attestationData2) {
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

        bytes memory _attestationData1 = _createAtestationData(receipt1, allocationIDPrivateKey);
        bytes memory _attestationData2 = _createAtestationData(receipt2, allocationIDPrivateKey);
        return (_attestationData1, _attestationData2);
    }

    function _createAtestationData(
        Attestation.Receipt memory receipt,
        uint256 signer
    ) private view returns (bytes memory attestationData) {
        bytes32 digest = disputeManager.encodeReceipt(receipt);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, digest);

        return abi.encodePacked(receipt.requestCID, receipt.responseCID, receipt.subgraphDeploymentId, r, s, v);
    }
}
