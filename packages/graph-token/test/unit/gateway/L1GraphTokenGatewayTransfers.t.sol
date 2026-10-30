// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IBridge } from "@graphprotocol/interfaces/contracts/contracts/arbitrum/IBridge.sol";
import { ITokenGateway } from "@graphprotocol/interfaces/contracts/contracts/arbitrum/ITokenGateway.sol";
import { L1GraphTokenGatewaySharedTest } from "./L1GraphTokenGatewayShared.t.sol";
import { IL1GraphTokenGatewayLike } from "../interfaces/IL1GraphTokenGatewayLike.sol";
import { IInboxMockLike } from "../interfaces/IArbitrumMocksLike.sol";

/// Cases from the "after configuring and unpausing" context
contract L1GraphTokenGatewayTransfersTest is L1GraphTokenGatewaySharedTest {
    uint8 internal constant L1_MESSAGE_TYPE_SUBMIT_RETRYABLE_TX = 9;
    uint160 internal constant L1_TO_L2_ALIAS_OFFSET = uint160(0x1111000000000000000000000000000000001111);

    bytes internal notEmptyCallHookData = hex"12";

    function setUp() public override {
        super.setUp();
        _configureL1Bridge();
    }

    function _applyL1ToL2Alias(address l1Address) internal pure returns (address) {
        unchecked {
            return address(uint160(l1Address) + L1_TO_L2_ALIAS_OFFSET);
        }
    }

    /// Message data the InboxMock builds for the retryable ticket
    function _createMsgData(bytes memory callHookData) internal view returns (bytes memory) {
        bytes memory outboundData = abi.encodeCall(
            ITokenGateway.finalizeInboundTransfer,
            (address(grt), tokenSender, l2Receiver, 10 ether, callHookData)
        );
        assertEq(
            l1Gateway.getOutboundCalldata(address(grt), tokenSender, l2Receiver, 10 ether, callHookData),
            outboundData
        );
        return
            abi.encodePacked(
                uint256(uint160(l2GatewayMock)),
                uint256(0),
                DEFAULT_ETH_VALUE,
                MAX_SUBMISSION_COST,
                uint256(uint160(_applyL1ToL2Alias(tokenSender))),
                uint256(uint160(_applyL1ToL2Alias(tokenSender))),
                MAX_GAS,
                GAS_PRICE_BID,
                outboundData.length,
                outboundData
            );
    }

    function _testValidOutboundTransfer(address signer, bytes memory data, bytes memory callHookData) internal {
        bytes memory msgData = _createMsgData(callHookData);
        bytes32 msgDataHash = keccak256(msgData);
        // The real bridge would emit the InboxAccs entry that came before this one, but the mock
        // emits this one, which lets us validate all the parameters we sent
        bytes32 expectedInboxAccsEntry = keccak256(
            abi.encodePacked(address(inboxMock), L1_MESSAGE_TYPE_SUBMIT_RETRYABLE_TX, address(l1Gateway), msgDataHash)
        );
        // The bridge mock returns an incrementing seqNum starting at 1
        uint256 expectedSeqNum = 1;

        vm.expectEmit(address(bridgeMock));
        emit IBridge.MessageDelivered(
            expectedSeqNum,
            expectedInboxAccsEntry,
            address(inboxMock),
            L1_MESSAGE_TYPE_SUBMIT_RETRYABLE_TX,
            address(l1Gateway),
            msgDataHash
        );
        vm.expectEmit(address(inboxMock));
        emit IInboxMockLike.InboxMessageDelivered(1, msgData);
        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.DepositInitiated(address(grt), tokenSender, l2Receiver, expectedSeqNum, 10 ether);
        vm.prank(signer);
        l1Gateway.outboundTransfer{ value: DEFAULT_ETH_VALUE }(
            address(grt),
            l2Receiver,
            10 ether,
            MAX_GAS,
            GAS_PRICE_BID,
            data
        );

        assertEq(grt.balanceOf(address(bridgeEscrow)), 10 ether);
        assertEq(grt.balanceOf(tokenSender), 990 ether);
    }

    /// The real outbox would require a proof validating that the tx was initiated by
    /// the L2 gateway, but the mock just executes unconditionally
    function _executeInbound(address l2Sender, uint256 amount) internal {
        bytes memory encodedCalldata = abi.encodeCall(
            ITokenGateway.finalizeInboundTransfer,
            (address(grt), l2Receiver, tokenSender, amount, abi.encode(uint256(0), bytes("")))
        );
        vm.prank(tokenSender);
        outboxMock.executeTransaction(
            0,
            new bytes32[](0),
            0,
            l2Sender,
            address(l1Gateway),
            1337,
            block.number,
            133701337,
            0,
            encodedCalldata
        );
    }

    function _approveAndTransfer() internal {
        vm.prank(tokenSender);
        grt.approve(address(l1Gateway), 10 ether);
        _testValidOutboundTransfer(tokenSender, defaultData, "");
    }

    // -- updateL2MintAllowance --

    function test_UpdateL2MintAllowance_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(pauseGuardian);
        l1Gateway.updateL2MintAllowance(1 ether, block.number);
    }

    function test_UpdateL2MintAllowance_RevertWhen_FutureOrCurrentBlock() public {
        vm.roll(100);
        uint256 issuancePerBlock = 120 ether;

        vm.startPrank(governor);
        vm.expectRevert(bytes("BLOCK_MUST_BE_PAST"));
        l1Gateway.updateL2MintAllowance(issuancePerBlock, block.number + 1);

        vm.expectRevert(bytes("BLOCK_MUST_BE_PAST"));
        l1Gateway.updateL2MintAllowance(issuancePerBlock, block.number);

        uint256 issuanceUpdatedAtBlock = block.number - 1;
        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.L2MintAllowanceUpdated(0, issuancePerBlock, issuanceUpdatedAtBlock);
        l1Gateway.updateL2MintAllowance(issuancePerBlock, issuanceUpdatedAtBlock);
        vm.stopPrank();
    }

    function test_UpdateL2MintAllowance_RevertWhen_BlockNotIncrementing() public {
        vm.roll(100);
        uint256 issuancePerBlock = 120 ether;
        uint256 issuanceUpdatedAtBlock = block.number - 1;

        vm.startPrank(governor);
        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.L2MintAllowanceUpdated(0, issuancePerBlock, issuanceUpdatedAtBlock);
        l1Gateway.updateL2MintAllowance(issuancePerBlock, issuanceUpdatedAtBlock);

        vm.expectRevert(bytes("BLOCK_MUST_BE_INCREMENTING"));
        l1Gateway.updateL2MintAllowance(issuancePerBlock, issuanceUpdatedAtBlock);

        vm.expectRevert(bytes("BLOCK_MUST_BE_INCREMENTING"));
        l1Gateway.updateL2MintAllowance(issuancePerBlock, issuanceUpdatedAtBlock - 1);

        vm.roll(block.number + 1);
        uint256 nextUpdateBlock = issuanceUpdatedAtBlock + 1;
        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.L2MintAllowanceUpdated(
            issuancePerBlock * (nextUpdateBlock - issuanceUpdatedAtBlock),
            issuancePerBlock,
            nextUpdateBlock
        );
        l1Gateway.updateL2MintAllowance(issuancePerBlock, nextUpdateBlock);
        vm.stopPrank();
    }

    function test_UpdateL2MintAllowance_AccumulatesUpToSpecifiedBlock() public {
        vm.roll(100);
        uint256 issuancePerBlock = 120 ether;
        uint256 issuanceUpdatedAtBlock = block.number - 3;

        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.L2MintAllowanceUpdated(0, issuancePerBlock, issuanceUpdatedAtBlock);
        vm.prank(governor);
        l1Gateway.updateL2MintAllowance(issuancePerBlock, issuanceUpdatedAtBlock);

        assertEq(
            l1Gateway.accumulatedL2MintAllowanceAtBlock(block.number),
            issuancePerBlock * (block.number - issuanceUpdatedAtBlock)
        );
        assertEq(l1Gateway.accumulatedL2MintAllowanceSnapshot(), 0);
        assertEq(l1Gateway.l2MintAllowancePerBlock(), issuancePerBlock);
        assertEq(l1Gateway.lastL2MintAllowanceUpdateBlock(), issuanceUpdatedAtBlock);

        vm.roll(block.number + 10);

        uint256 newIssuancePerBlock = 200 ether;
        uint256 newIssuanceUpdatedAtBlock = block.number - 2;
        uint256 expectedAccumulatedSnapshot = issuancePerBlock * (newIssuanceUpdatedAtBlock - issuanceUpdatedAtBlock);

        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.L2MintAllowanceUpdated(
            expectedAccumulatedSnapshot,
            newIssuancePerBlock,
            newIssuanceUpdatedAtBlock
        );
        vm.prank(governor);
        l1Gateway.updateL2MintAllowance(newIssuancePerBlock, newIssuanceUpdatedAtBlock);

        assertEq(
            l1Gateway.accumulatedL2MintAllowanceAtBlock(block.number),
            expectedAccumulatedSnapshot + newIssuancePerBlock * (block.number - newIssuanceUpdatedAtBlock)
        );
        assertEq(l1Gateway.accumulatedL2MintAllowanceSnapshot(), expectedAccumulatedSnapshot);
        assertEq(l1Gateway.l2MintAllowancePerBlock(), newIssuancePerBlock);
        assertEq(l1Gateway.lastL2MintAllowanceUpdateBlock(), newIssuanceUpdatedAtBlock);
    }

    // -- setL2MintAllowanceParametersManual --

    function test_SetL2MintAllowanceParametersManual_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(pauseGuardian);
        l1Gateway.setL2MintAllowanceParametersManual(0, 1 ether, block.number);
    }

    function test_SetL2MintAllowanceParametersManual_RevertWhen_FutureOrCurrentBlock() public {
        vm.roll(100);
        uint256 issuancePerBlock = 120 ether;

        vm.startPrank(governor);
        vm.expectRevert(bytes("BLOCK_MUST_BE_PAST"));
        l1Gateway.setL2MintAllowanceParametersManual(0, issuancePerBlock, block.number + 1);

        vm.expectRevert(bytes("BLOCK_MUST_BE_PAST"));
        l1Gateway.setL2MintAllowanceParametersManual(0, issuancePerBlock, block.number);

        uint256 issuanceUpdatedAtBlock = block.number - 1;
        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.L2MintAllowanceUpdated(0, issuancePerBlock, issuanceUpdatedAtBlock);
        l1Gateway.setL2MintAllowanceParametersManual(0, issuancePerBlock, issuanceUpdatedAtBlock);
        vm.stopPrank();
    }

    function test_SetL2MintAllowanceParametersManual_SetsSnapshotManually() public {
        vm.roll(100);
        uint256 issuancePerBlock = 120 ether;
        uint256 issuanceUpdatedAtBlock = block.number - 3;
        uint256 snapshotValue = 10 ether;

        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.L2MintAllowanceUpdated(snapshotValue, issuancePerBlock, issuanceUpdatedAtBlock);
        vm.prank(governor);
        l1Gateway.setL2MintAllowanceParametersManual(snapshotValue, issuancePerBlock, issuanceUpdatedAtBlock);

        assertEq(
            l1Gateway.accumulatedL2MintAllowanceAtBlock(block.number),
            snapshotValue + issuancePerBlock * (block.number - issuanceUpdatedAtBlock)
        );
        assertEq(l1Gateway.accumulatedL2MintAllowanceSnapshot(), snapshotValue);
        assertEq(l1Gateway.l2MintAllowancePerBlock(), issuancePerBlock);
        assertEq(l1Gateway.lastL2MintAllowanceUpdateBlock(), issuanceUpdatedAtBlock);

        vm.roll(block.number + 10);

        uint256 newIssuancePerBlock = 200 ether;
        uint256 newIssuanceUpdatedAtBlock = block.number - 2;
        uint256 newSnapshotValue = 10 ether;

        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.L2MintAllowanceUpdated(
            newSnapshotValue,
            newIssuancePerBlock,
            newIssuanceUpdatedAtBlock
        );
        vm.prank(governor);
        l1Gateway.setL2MintAllowanceParametersManual(newSnapshotValue, newIssuancePerBlock, newIssuanceUpdatedAtBlock);

        assertEq(
            l1Gateway.accumulatedL2MintAllowanceAtBlock(block.number),
            newSnapshotValue + newIssuancePerBlock * (block.number - newIssuanceUpdatedAtBlock)
        );
        assertEq(l1Gateway.accumulatedL2MintAllowanceSnapshot(), newSnapshotValue);
        assertEq(l1Gateway.l2MintAllowancePerBlock(), newIssuancePerBlock);
        assertEq(l1Gateway.lastL2MintAllowanceUpdateBlock(), newIssuanceUpdatedAtBlock);
    }

    // -- calculateL2TokenAddress --

    function test_CalculateL2TokenAddress_ReturnsL2TokenAddress() public view {
        assertEq(l1Gateway.calculateL2TokenAddress(address(grt)), l2GRTMock);
    }

    function test_CalculateL2TokenAddress_ReturnsZeroForOtherAddress() public view {
        assertEq(l1Gateway.calculateL2TokenAddress(tokenSender), address(0));
    }

    // -- outboundTransfer --

    function test_OutboundTransfer_RevertWhen_WrongToken() public {
        vm.expectRevert(bytes("TOKEN_NOT_GRT"));
        vm.prank(tokenSender);
        l1Gateway.outboundTransfer{ value: DEFAULT_ETH_VALUE }(
            tokenSender,
            l2Receiver,
            10 ether,
            MAX_GAS,
            GAS_PRICE_BID,
            defaultData
        );
    }

    function test_OutboundTransfer_EscrowsTokensAndCreatesRetryableTicket() public {
        _approveAndTransfer();
    }

    function test_OutboundTransfer_DecodesSenderFromRouter() public {
        vm.prank(tokenSender);
        grt.approve(address(l1Gateway), 10 ether);
        bytes memory routerEncodedData = abi.encode(tokenSender, defaultData);
        _testValidOutboundTransfer(routerMock, routerEncodedData, "");
    }

    function test_OutboundTransfer_RevertWhen_NoSubmissionCost() public {
        vm.prank(tokenSender);
        grt.approve(address(l1Gateway), 10 ether);

        vm.expectRevert(bytes("NO_SUBMISSION_COST"));
        vm.prank(tokenSender);
        l1Gateway.outboundTransfer{ value: DEFAULT_ETH_VALUE }(
            address(grt),
            l2Receiver,
            10 ether,
            MAX_GAS,
            GAS_PRICE_BID,
            abi.encode(uint256(0), bytes(""))
        );
    }

    function test_OutboundTransfer_RevertWhen_CallhookSenderNotAllowlisted() public {
        vm.prank(tokenSender);
        grt.approve(address(l1Gateway), 10 ether);

        vm.expectRevert(bytes("CALL_HOOK_DATA_NOT_ALLOWED"));
        vm.prank(tokenSender);
        l1Gateway.outboundTransfer{ value: DEFAULT_ETH_VALUE }(
            address(grt),
            l2Receiver,
            10 ether,
            MAX_GAS,
            GAS_PRICE_BID,
            abi.encode(MAX_SUBMISSION_COST, notEmptyCallHookData)
        );
    }

    function test_OutboundTransfer_AllowsCallhookFromAllowlistedSender() public {
        // Make the sender a contract so that it can be allowed to send callhooks
        vm.etch(tokenSender, hex"1234");
        vm.prank(governor);
        l1Gateway.addToCallhookAllowlist(tokenSender);
        vm.prank(tokenSender);
        grt.approve(address(l1Gateway), 10 ether);

        _testValidOutboundTransfer(
            tokenSender,
            abi.encode(MAX_SUBMISSION_COST, notEmptyCallHookData),
            notEmptyCallHookData
        );
    }

    function test_OutboundTransfer_RevertWhen_InsufficientBalance() public {
        vm.prank(tokenSender);
        grt.approve(address(l1Gateway), 1001 ether);

        vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
        vm.prank(tokenSender);
        l1Gateway.outboundTransfer{ value: DEFAULT_ETH_VALUE }(
            address(grt),
            l2Receiver,
            1001 ether,
            MAX_GAS,
            GAS_PRICE_BID,
            defaultData
        );
    }

    // -- finalizeInboundTransfer --

    function test_FinalizeInboundTransfer_RevertWhen_NotBridge() public {
        vm.expectRevert(bytes("NOT_FROM_BRIDGE"));
        vm.prank(tokenSender);
        l1Gateway.finalizeInboundTransfer(address(grt), l2Receiver, tokenSender, 10 ether, defaultData);
    }

    function test_FinalizeInboundTransfer_RevertWhen_NotFromL2Gateway() public {
        vm.expectRevert(bytes("ONLY_COUNTERPART_GATEWAY"));
        _executeInbound(l2Receiver, 10 ether); // l2Receiver is not the L2 gateway
    }

    function test_FinalizeInboundTransfer_RevertWhen_NoTokensOrAllowance() public {
        // Should never happen, but the gateway must still revert
        vm.expectRevert(bytes("INVALID_L2_MINT_AMOUNT"));
        _executeInbound(l2GatewayMock, 10 ether);
    }

    function test_FinalizeInboundTransfer_RevertWhen_RevokedFromEscrow() public {
        _approveAndTransfer();
        // The escrow holds 10 GRT, but the gateway can no longer move them
        vm.prank(governor);
        bridgeEscrow.revokeAll(address(l1Gateway));

        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));
        _executeInbound(l2GatewayMock, 8 ether);
    }

    function test_FinalizeInboundTransfer_SendsTokensOutOfEscrow() public {
        _approveAndTransfer();

        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.WithdrawalFinalized(address(grt), l2Receiver, tokenSender, 0, 8 ether);
        _executeInbound(l2GatewayMock, 8 ether);

        assertEq(grt.balanceOf(address(bridgeEscrow)), 2 ether);
        assertEq(grt.balanceOf(tokenSender), 998 ether);
    }

    function test_FinalizeInboundTransfer_MintsUpToL2MintAllowance() public {
        _approveAndTransfer();

        // Start accruing L2 mint allowance at 2 GRT per block
        uint256 updateBlock = block.number;
        vm.roll(updateBlock + 1);
        vm.prank(governor);
        l1Gateway.updateL2MintAllowance(2 ether, updateBlock);
        vm.roll(updateBlock + 4);
        uint256 allowance = 2 ether * (block.number - updateBlock);
        assertEq(allowance, 8 ether);

        // The escrow holds 10 GRT
        uint256 amount = 10 ether + allowance;
        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.TokensMintedFromL2(allowance);
        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.WithdrawalFinalized(address(grt), l2Receiver, tokenSender, 0, amount);
        _executeInbound(l2GatewayMock, amount);

        assertEq(l1Gateway.totalMintedFromL2(), allowance);
        assertEq(l1Gateway.accumulatedL2MintAllowanceAtBlock(block.number), allowance);
        assertEq(grt.balanceOf(address(bridgeEscrow)), 0);
        assertEq(grt.balanceOf(tokenSender), 990 ether + amount);
    }

    function test_FinalizeInboundTransfer_RevertWhen_OverL2MintAllowance() public {
        _approveAndTransfer();

        // Start accruing L2 mint allowance at 2 GRT per block
        uint256 updateBlock = block.number;
        vm.roll(updateBlock + 1);
        vm.prank(governor);
        l1Gateway.updateL2MintAllowance(2 ether, updateBlock);
        vm.roll(updateBlock + 4);
        uint256 allowance = 2 ether * (block.number - updateBlock);
        assertEq(allowance, 8 ether);

        // The escrow holds 10 GRT
        vm.expectRevert(bytes("INVALID_L2_MINT_AMOUNT"));
        _executeInbound(l2GatewayMock, 10 ether + allowance + 0.001 ether);
    }
}
