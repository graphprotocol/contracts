// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "../../contracts/interfaces/IDisputeManager.sol";
import { Attestation } from "../../contracts/libraries/Attestation.sol";

import { GraphBaseTest } from "../GraphBaseTest.t.sol";

contract DisputeManagerTest is GraphBaseTest {
    using PPMMath for uint256;

    /*
     * VARIABLES
     */

    uint256 allocationIDPrivateKey;
    address allocationID;

    /*
     * MODIFIERS
     */

    modifier useIndexer {
        vm.startPrank(users.indexer);
        _;
        vm.stopPrank();
    }

    modifier useFisherman {
        vm.startPrank(users.fisherman);
        _;
        vm.stopPrank();
    }

    modifier useProvision(uint256 tokens) {
        vm.assume(tokens > minimumProvisionTokens);
        vm.assume(tokens < 10_000_000_000 ether);
        staking.provision(tokens, address(subgraphService), maxSlashingPercentage, disputePeriod);
        bytes32 subgraphDeployment = keccak256(abi.encodePacked("Subgraph Deployment ID"));
        bytes32 digest = subgraphService.encodeAllocationProof(users.indexer, allocationID);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(allocationIDPrivateKey, digest);

        subgraphService.register(users.indexer, abi.encode("url", "geoHash", address(0)));

        bytes memory data = abi.encode(subgraphDeployment, tokens, allocationID, abi.encodePacked(r, s, v));
        subgraphService.startService(users.indexer, data);
        _;
    }

    /*
     * SET UP
     */

    function setUp() public override {
        super.setUp();
        (allocationID, allocationIDPrivateKey) = makeAddrAndKey("allocationId");
    }

    /*
     * HELPERS
     */

    function _createIndexingDispute(address _allocationID, bytes32 _poi, uint256 tokens) internal returns (bytes32 disputeID) {
        address msgSender;
        (, msgSender,) = vm.readCallers();
        resetPrank(users.fisherman);
        token.approve(address(disputeManager), tokens);
        bytes32 _disputeID = disputeManager.createIndexingDispute(_allocationID, _poi, tokens);
        resetPrank(msgSender);
        return _disputeID;
    }

    function _createQueryDispute(uint256 tokens) internal returns (bytes32 disputeID) {
        address msgSender;
        (, msgSender,) = vm.readCallers();
        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = Attestation.Receipt({
            requestCID: keccak256(abi.encodePacked("Request CID")),
            responseCID: keccak256(abi.encodePacked("Response CID")),
            subgraphDeploymentId: keccak256(abi.encodePacked("Subgraph Deployment ID"))
        });
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);

        token.approve(address(disputeManager), tokens);
        bytes32 _disputeID = disputeManager.createQueryDispute(attestationData, tokens);
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
