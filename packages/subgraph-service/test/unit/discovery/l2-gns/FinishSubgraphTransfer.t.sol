// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { GNSHelpers } from "../shared/GNSHelpers.t.sol";
import { IL2GNSLike } from "../interfaces/IL2GNSLike.sol";

contract FinishSubgraphTransferTest is GNSHelpers {
    bytes32 internal constant METADATA = keccak256("metadata");

    // -- finishing a subgraph transfer from L1 --

    function test_FinishSubgraphTransfer_PublishesAndMintsSignalWithNoTax() public {
        uint256 l1SubgraphId = _l1SubgraphId();
        uint256 l2SubgraphId = _receiveSubgraph(l1SubgraphId);
        uint256 expectedSignal = curation.tokensToSignalNoTax(DEPLOYMENT_ID_0, L1_CURATED_TOKENS);
        // vSignal is zero before the transfer, so nSignal is minted 1:1
        uint256 expectedNSignalEmitted = gns.vSignalToNSignal(l2SubgraphId, expectedSignal);

        vm.expectEmit(address(gns));
        emit IL2GNSLike.SignalMinted(l2SubgraphId, me, expectedNSignalEmitted, expectedSignal, L1_CURATED_TOKENS);
        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphUpgraded(l2SubgraphId, expectedSignal, L1_CURATED_TOKENS, DEPLOYMENT_ID_0);
        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphMetadataUpdated(l2SubgraphId, L1_SUBGRAPH_METADATA);
        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphPublished(l2SubgraphId, DEPLOYMENT_ID_0, DEFAULT_RESERVE_RATIO);
        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphVersionUpdated(l2SubgraphId, DEPLOYMENT_ID_0, L1_VERSION_METADATA);
        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphL2TransferFinalized(l2SubgraphId);
        vm.prank(me);
        gns.finishSubgraphTransferFromL1(l2SubgraphId, DEPLOYMENT_ID_0, L1_SUBGRAPH_METADATA, L1_VERSION_METADATA);

        _assertFinished(l2SubgraphId, expectedSignal);
        uint256 expectedNSignal = gns.vSignalToNSignal(l2SubgraphId, expectedSignal);
        assertEq(gns.getCuratorSignal(l2SubgraphId, me), expectedNSignal);
        assertEq(expectedNSignal, expectedNSignalEmitted);
    }

    function test_FinishSubgraphTransfer_RevertWhen_NotOwner() public {
        uint256 l2SubgraphId = _receiveSubgraph(_l1SubgraphId());
        vm.expectRevert(bytes("GNS: Must be authorized"));
        vm.prank(other);
        gns.finishSubgraphTransferFromL1(l2SubgraphId, DEPLOYMENT_ID_0, L1_SUBGRAPH_METADATA, L1_VERSION_METADATA);
    }

    function test_FinishSubgraphTransfer_RevertWhen_SubgraphDoesNotExist() public {
        uint256 l2SubgraphId = gns.getAliasedL2SubgraphID(_l1SubgraphId());
        vm.expectRevert(bytes("ERC721: owner query for nonexistent token"));
        vm.prank(me);
        gns.finishSubgraphTransferFromL1(l2SubgraphId, DEPLOYMENT_ID_0, METADATA, METADATA);
    }

    function test_FinishSubgraphTransfer_RevertWhen_NotTransferredFromL1() public {
        uint256 l2SubgraphId = _publishNewSubgraph(me, DEPLOYMENT_ID_0);
        vm.expectRevert(bytes("INVALID_SUBGRAPH"));
        vm.prank(me);
        gns.finishSubgraphTransferFromL1(l2SubgraphId, DEPLOYMENT_ID_0, METADATA, METADATA);
    }

    function test_FinishSubgraphTransfer_ToPreCuratedDeployment() public {
        uint256 l2SubgraphId = _receiveSubgraph(_l1SubgraphId());

        // Expected signal computed before the pre-curation
        uint256 expectedSignal = curation.tokensToSignalNoTax(DEPLOYMENT_ID_0, L1_CURATED_TOKENS);
        vm.startPrank(me);
        grt.approve(address(curation), 100 ether);
        curation.mint(DEPLOYMENT_ID_0, 100 ether, 0);
        vm.stopPrank();
        assertEq(curation.getCurationPoolTokens(DEPLOYMENT_ID_0), 100 ether);

        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphUpgraded(l2SubgraphId, expectedSignal, L1_CURATED_TOKENS, DEPLOYMENT_ID_0);
        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphMetadataUpdated(l2SubgraphId, L1_SUBGRAPH_METADATA);
        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphPublished(l2SubgraphId, DEPLOYMENT_ID_0, DEFAULT_RESERVE_RATIO);
        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphVersionUpdated(l2SubgraphId, DEPLOYMENT_ID_0, L1_VERSION_METADATA);
        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphL2TransferFinalized(l2SubgraphId);
        vm.prank(me);
        gns.finishSubgraphTransferFromL1(l2SubgraphId, DEPLOYMENT_ID_0, L1_SUBGRAPH_METADATA, L1_VERSION_METADATA);

        _assertFinished(l2SubgraphId, expectedSignal);
        assertEq(curation.getCurationPoolTokens(DEPLOYMENT_ID_0), 100 ether + L1_CURATED_TOKENS);
    }

    function test_FinishSubgraphTransfer_RevertWhen_DeploymentIDZero() public {
        uint256 l2SubgraphId = _receiveSubgraph(_l1SubgraphId());
        vm.expectRevert(bytes("GNS: deploymentID != 0"));
        vm.prank(me);
        gns.finishSubgraphTransferFromL1(l2SubgraphId, bytes32(0), METADATA, METADATA);
    }

    function test_FinishSubgraphTransfer_RevertWhen_AlreadyFinished() public {
        uint256 l2SubgraphId = _receiveSubgraph(_l1SubgraphId());
        vm.startPrank(me);
        gns.finishSubgraphTransferFromL1(l2SubgraphId, DEPLOYMENT_ID_0, METADATA, METADATA);

        vm.expectRevert(bytes("ALREADY_DONE"));
        gns.finishSubgraphTransferFromL1(l2SubgraphId, DEPLOYMENT_ID_0, METADATA, METADATA);
        vm.stopPrank();
    }

    function _receiveSubgraph(uint256 l1SubgraphId) internal returns (uint256) {
        gatewayMock.deliver(
            address(gns),
            l1GNS,
            L1_CURATED_TOKENS,
            _callhookData(RECEIVE_SUBGRAPH_CODE, l1SubgraphId, me)
        );
        return gns.getAliasedL2SubgraphID(l1SubgraphId);
    }

    function _assertFinished(uint256 l2SubgraphId, uint256 expectedSignal) internal view {
        Subgraph memory s = _subgraph(l2SubgraphId);
        (, bool l2Done, ) = gns.subgraphL2TransferData(l2SubgraphId);
        assertEq(s.vSignal, expectedSignal);
        assertTrue(l2Done);
        assertFalse(s.disabled);
        assertEq(s.subgraphDeploymentID, DEPLOYMENT_ID_0);
    }
}
