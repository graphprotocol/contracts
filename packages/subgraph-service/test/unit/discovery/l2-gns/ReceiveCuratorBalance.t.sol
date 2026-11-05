// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { GNSHelpers } from "../shared/GNSHelpers.t.sol";
import { IL2GNSLike } from "../interfaces/IL2GNSLike.sol";

contract ReceiveCuratorBalanceTest is GNSHelpers {
    // -- claiming a curator balance with a message from L1 (onTokenTransfer) --

    function test_ReceiveCuratorBalance_AssignsBalanceToBeneficiary() public {
        uint256 l1SubgraphId = _l1SubgraphId();
        _transferMockSubgraphFromL1(l1SubgraphId, L1_CURATED_TOKENS);
        uint256 l2SubgraphId = gns.getAliasedL2SubgraphID(l1SubgraphId);
        uint256 l2OwnerSignalBefore = gns.getCuratorSignal(l2SubgraphId, me);

        uint256 newCuratorTokens = 10 ether;
        vm.expectEmit(address(gns));
        emit IL2GNSLike.CuratorBalanceReceived(l1SubgraphId, l2SubgraphId, other, newCuratorTokens);
        gatewayMock.deliver(
            address(gns),
            l1GNS,
            newCuratorTokens,
            _callhookData(RECEIVE_CURATOR_BALANCE_CODE, l1SubgraphId, other)
        );

        uint256 expectedNewCuratorSignal = gns.vSignalToNSignal(
            l2SubgraphId,
            curation.tokensToSignalNoTax(DEPLOYMENT_ID_0, newCuratorTokens)
        );
        assertEq(gns.getCuratorSignal(l2SubgraphId, me), l2OwnerSignalBefore);
        assertEq(gns.getCuratorSignal(l2SubgraphId, other), expectedNewCuratorSignal);
    }

    function test_ReceiveCuratorBalance_AddsToExistingSignal() public {
        uint256 l1SubgraphId = _l1SubgraphId();
        _transferMockSubgraphFromL1(l1SubgraphId, L1_CURATED_TOKENS);
        uint256 l2SubgraphId = gns.getAliasedL2SubgraphID(l1SubgraphId);

        vm.prank(governor);
        grt.mint(other, 10 ether);
        vm.startPrank(other);
        grt.approve(address(gns), 10 ether);
        gns.mintSignal(l2SubgraphId, 10 ether, 0);
        vm.stopPrank();
        uint256 prevSignal = gns.getCuratorSignal(l2SubgraphId, other);

        uint256 newCuratorTokens = 10 ether;
        vm.expectEmit(address(gns));
        emit IL2GNSLike.CuratorBalanceReceived(l1SubgraphId, l2SubgraphId, other, newCuratorTokens);
        gatewayMock.deliver(
            address(gns),
            l1GNS,
            newCuratorTokens,
            _callhookData(RECEIVE_CURATOR_BALANCE_CODE, l1SubgraphId, other)
        );

        uint256 expectedNewCuratorSignal = gns.vSignalToNSignal(
            l2SubgraphId,
            curation.tokensToSignalNoTax(DEPLOYMENT_ID_0, newCuratorTokens)
        );
        assertEq(gns.getCuratorSignal(l2SubgraphId, other), prevSignal + expectedNewCuratorSignal);
    }

    function test_ReceiveCuratorBalance_RevertWhen_CallerNotGateway() public {
        uint256 l1SubgraphId = _l1SubgraphId();
        _transferMockSubgraphFromL1(l1SubgraphId, L1_CURATED_TOKENS);
        bytes memory data = _callhookData(RECEIVE_CURATOR_BALANCE_CODE, l1SubgraphId, me);
        vm.expectRevert(bytes("ONLY_GATEWAY"));
        vm.prank(me);
        gns.onTokenTransfer(l1GNS, 1 ether, data);
    }

    function test_ReceiveCuratorBalance_RevertWhen_L1SenderNotL1GNS() public {
        uint256 l1SubgraphId = _l1SubgraphId();
        _transferMockSubgraphFromL1(l1SubgraphId, L1_CURATED_TOKENS);
        bytes memory data = _callhookData(RECEIVE_CURATOR_BALANCE_CODE, l1SubgraphId, me);
        vm.expectRevert(bytes("ONLY_L1_GNS_THROUGH_BRIDGE"));
        gatewayMock.deliver(address(gns), me, 1 ether, data);
    }

    function test_ReceiveCuratorBalance_ReturnsTokensWhenSubgraphDoesNotExist() public {
        _assertReturnedToBeneficiary(_l1SubgraphId());
    }

    function test_ReceiveCuratorBalance_ReturnsTokensForL2NativeSubgraph() public {
        // Only happens on a subgraph ID clash, but the behaviour must be well defined
        uint256 l2SubgraphId = _publishNewSubgraph(me, DEPLOYMENT_ID_0);
        _assertReturnedToBeneficiary(l2SubgraphId);
    }

    function test_ReceiveCuratorBalance_ReturnsTokensWhenTransferNotFinished() public {
        uint256 l1SubgraphId = _l1SubgraphId();
        gatewayMock.deliver(
            address(gns),
            l1GNS,
            L1_CURATED_TOKENS,
            _callhookData(RECEIVE_SUBGRAPH_CODE, l1SubgraphId, me)
        );

        // The subgraph exists, but the transfer is not finished
        _assertReturnedToBeneficiary(l1SubgraphId);
    }

    function test_ReceiveCuratorBalance_ReturnsTokensWhenDeprecatedAfterTransfer() public {
        uint256 l1SubgraphId = _l1SubgraphId();
        _transferMockSubgraphFromL1(l1SubgraphId, L1_CURATED_TOKENS);
        uint256 l2SubgraphId = gns.getAliasedL2SubgraphID(l1SubgraphId);
        vm.prank(me);
        gns.deprecateSubgraph(l2SubgraphId);

        // Transferred, but deprecated now
        _assertReturnedToBeneficiary(l1SubgraphId);
    }

    function _assertReturnedToBeneficiary(uint256 l1SubgraphId) internal {
        uint256 curatorTokensBefore = grt.balanceOf(me);
        uint256 gnsBalanceBefore = grt.balanceOf(address(gns));

        vm.expectEmit(address(gns));
        emit IL2GNSLike.CuratorBalanceReturnedToBeneficiary(l1SubgraphId, me, 1 ether);
        gatewayMock.deliver(
            address(gns),
            l1GNS,
            1 ether,
            _callhookData(RECEIVE_CURATOR_BALANCE_CODE, l1SubgraphId, me)
        );

        assertEq(grt.balanceOf(me), curatorTokensBefore + 1 ether);
        // The gateway mints the tokens that are sent on to the curator
        assertEq(grt.balanceOf(address(gns)), gnsBalanceBefore);
    }
}
