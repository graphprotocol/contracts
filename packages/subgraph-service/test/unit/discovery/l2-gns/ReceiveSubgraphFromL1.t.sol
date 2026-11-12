// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { GNSHelpers } from "../shared/GNSHelpers.t.sol";
import { IL2GNSLike } from "../interfaces/IL2GNSLike.sol";

contract ReceiveSubgraphFromL1Test is GNSHelpers {
    // -- receiving a subgraph from L1 (onTokenTransfer) --

    function test_ReceiveSubgraphFromL1_RevertWhen_CallerNotGateway() public {
        bytes memory data = _callhookData(RECEIVE_SUBGRAPH_CODE, _l1SubgraphId(), me);
        vm.expectRevert(bytes("ONLY_GATEWAY"));
        vm.prank(me);
        gns.onTokenTransfer(l1GNS, L1_CURATED_TOKENS, data);
    }

    function test_ReceiveSubgraphFromL1_RevertWhen_L1SenderNotL1GNS() public {
        bytes memory data = _callhookData(RECEIVE_SUBGRAPH_CODE, _l1SubgraphId(), me);
        vm.expectRevert(bytes("ONLY_L1_GNS_THROUGH_BRIDGE"));
        gatewayMock.deliver(address(gns), me, L1_CURATED_TOKENS, data);
    }

    function test_ReceiveSubgraphFromL1_CreatesDisabledSubgraph() public {
        uint256 l1SubgraphId = _l1SubgraphId();
        uint256 l2SubgraphId = gns.getAliasedL2SubgraphID(l1SubgraphId);

        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphReceivedFromL1(l1SubgraphId, l2SubgraphId, me, L1_CURATED_TOKENS);
        gatewayMock.deliver(
            address(gns),
            l1GNS,
            L1_CURATED_TOKENS,
            _callhookData(RECEIVE_SUBGRAPH_CODE, l1SubgraphId, me)
        );

        _assertReceivedSubgraph(l2SubgraphId);
    }

    function test_ReceiveSubgraphFromL1_DoesNotConflictWithLocalSubgraph() public {
        uint256 localSubgraphId = _publishNewSubgraph(me, DEPLOYMENT_ID_0);

        uint256 l1SubgraphId = _l1SubgraphId();
        uint256 l2SubgraphId = gns.getAliasedL2SubgraphID(l1SubgraphId);

        vm.expectEmit(address(gns));
        emit IL2GNSLike.SubgraphReceivedFromL1(l1SubgraphId, l2SubgraphId, me, L1_CURATED_TOKENS);
        gatewayMock.deliver(
            address(gns),
            l1GNS,
            L1_CURATED_TOKENS,
            _callhookData(RECEIVE_SUBGRAPH_CODE, l1SubgraphId, me)
        );

        _assertReceivedSubgraph(l2SubgraphId);

        assertNotEq(localSubgraphId, l2SubgraphId);
        Subgraph memory local = _subgraph(localSubgraphId);
        assertEq(local.vSignal, 0);
        assertEq(local.nSignal, 0);
        assertEq(local.subgraphDeploymentID, DEPLOYMENT_ID_0);
        assertEq(local.reserveRatio, DEFAULT_RESERVE_RATIO);
        assertFalse(local.disabled);
        assertEq(local.withdrawableGRT, 0);
    }

    // -- onTokenTransfer with invalid codes --

    function test_OnTokenTransferWithInvalidCodes_RevertWhen_InvalidCode() public {
        // Code 2 does not exist
        bytes memory data = _callhookData(2, 1337, me);
        vm.expectRevert(bytes("INVALID_CODE"));
        gatewayMock.deliver(address(gns), l1GNS, 1 ether, data);
    }

    function _assertReceivedSubgraph(uint256 l2SubgraphId) internal view {
        (uint256 tokens, bool l2Done, uint256 receivedBlock) = gns.subgraphL2TransferData(l2SubgraphId);
        assertEq(tokens, L1_CURATED_TOKENS);
        assertFalse(l2Done);
        assertEq(receivedBlock, block.number);

        Subgraph memory s = _subgraph(l2SubgraphId);
        assertEq(s.vSignal, 0);
        assertEq(s.nSignal, 0);
        assertEq(s.subgraphDeploymentID, bytes32(0));
        assertEq(s.reserveRatio, DEFAULT_RESERVE_RATIO);
        assertTrue(s.disabled);
        // Not the same as a deprecated subgraph
        assertEq(s.withdrawableGRT, 0);

        assertEq(gns.ownerOf(l2SubgraphId), me);
    }
}
