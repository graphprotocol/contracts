// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IGraphPayments } from "../../contracts/interfaces/IGraphPayments.sol";

import { HorizonStaking_Shared_Test } from "../shared/horizon-staking/HorizonStaking.t.sol";

contract GraphEscrowTest is HorizonStaking_Shared_Test {

    // Collector approve tests

    function testCollector_Approve() public {
        vm.prank(users.gateway);
        escrow.approveCollector(users.verifier, 1000 ether);

        (bool authorized,, uint256 thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, 0);
    }

    // Collector thaw tests

    function testCollector_Thaw() public {
        vm.startPrank(users.gateway);
        escrow.approveCollector(users.verifier, 1000 ether);
        escrow.thawCollector(users.verifier);
        vm.stopPrank();

        (bool authorized,, uint256 thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, block.timestamp + revokeCollectorThawingPeriod);
    }

    // Collector cancel thaw tests

    function testCollector_CancelThaw() public {
        vm.startPrank(users.gateway);
        escrow.approveCollector(users.verifier, 1000 ether);
        escrow.thawCollector(users.verifier);
        vm.stopPrank();

        (bool authorized,, uint256 thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, block.timestamp + revokeCollectorThawingPeriod);

        vm.prank(users.gateway);
        escrow.cancelThawCollector(users.verifier);

        (authorized,, thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, 0);
    }

    function testCollector_RevertWhen_CancelThawIsNotThawing() public {
        vm.startPrank(users.gateway);
        escrow.approveCollector(users.verifier, 1000 ether);
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.cancelThawCollector(users.verifier);
        vm.stopPrank();
    }

    // Collector revoke tests

    function testCollector_Revoke() public {
        vm.startPrank(users.gateway);
        escrow.approveCollector(users.verifier, 1000 ether);
        escrow.thawCollector(users.verifier);
        skip(revokeCollectorThawingPeriod + 1);
        escrow.revokeCollector(users.verifier);
        vm.stopPrank();

        (bool authorized,,) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(authorized, false);
    }

    function testCollector_RevertWhen_RevokeIsNotThawing() public {
        vm.startPrank(users.gateway);
        escrow.approveCollector(users.verifier, 1000 ether);
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.revokeCollector(users.verifier);
        vm.stopPrank();
    }

    function testCollector_RevertWhen_RevokeIsStillThawing() public {
        vm.startPrank(users.gateway);
        escrow.approveCollector(users.verifier, 1000 ether);
        escrow.thawCollector(users.verifier);
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowStillThawing(uint256,uint256)", block.timestamp, block.timestamp + revokeCollectorThawingPeriod);
        vm.expectRevert(expectedError);
        escrow.revokeCollector(users.verifier);
        vm.stopPrank();
    }

    // Deposit tests

    function testDeposit_Tokens() public {
        mint(users.gateway, 10000 ether);
        vm.startPrank(users.gateway);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(users.indexer, 1000 ether);
        vm.stopPrank();

        (uint256 indexerEscrowBalance,,) = escrow.escrowAccounts(users.gateway, users.indexer);
        assertEq(indexerEscrowBalance, 1000 ether);
    }

    function testDeposit_ManyDeposits() public {
        address otherIndexer = address(0xB3);
        address[] memory indexers = new address[](2);
        indexers[0] = users.indexer;
        indexers[1] = otherIndexer;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 ether;
        amounts[1] = 2000 ether;

        mint(users.gateway, 3000 ether);
        vm.startPrank(users.gateway);
        token.approve(address(escrow), 3000 ether);
        escrow.depositMany(indexers, amounts);
        vm.stopPrank();

        (uint256 indexerEscrowBalance,,) = escrow.escrowAccounts(users.gateway, users.indexer);
        assertEq(indexerEscrowBalance, 1000 ether);

        (uint256 otherIndexerEscrowBalance,,) = escrow.escrowAccounts(users.gateway, otherIndexer);
        assertEq(otherIndexerEscrowBalance, 2000 ether);
    }

    function testDeposit_RevertWhen_ManyDepositsInputsLengthMismatch() public {
        address otherIndexer = address(0xB3);
        address[] memory indexers = new address[](2);
        indexers[0] = users.indexer;
        indexers[1] = otherIndexer;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 ether;

        mint(users.gateway, 1000 ether);
        token.approve(address(escrow), 1000 ether);

        // revert
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowInputsLengthMismatch()");
        vm.expectRevert(expectedError);
        vm.prank(users.gateway);
        escrow.depositMany(indexers, amounts);
    }

    // Thaw tests

    function testThaw_Tokens() public {
        mint(users.gateway, 1000 ether);
        vm.startPrank(users.gateway);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(users.indexer, 1000 ether);
        escrow.thaw(users.indexer, 100 ether);
        vm.stopPrank();

        (, uint256 amountThawing,uint256 thawEndTimestamp) = escrow.escrowAccounts(users.gateway, users.indexer);
        assertEq(amountThawing, 100 ether);
        assertEq(thawEndTimestamp, block.timestamp + withdrawEscrowThawingPeriod);
    }

    function testThaw_RevertWhen_InsufficientThawAmount() public {
        mint(users.gateway, 1000 ether);
        vm.startPrank(users.gateway);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(users.indexer, 1000 ether);

        // revert
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowInsufficientThawAmount()");
        vm.expectRevert(expectedError);
        escrow.thaw(users.indexer, 0);
        vm.stopPrank();
    }

    function testThaw_RevertWhen_InsufficientAmount() public {
        mint(users.gateway, 1000 ether);
        vm.startPrank(users.gateway);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(users.indexer, 1000 ether);

        // revert
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowInsufficientAmount(uint256,uint256)", 1000 ether, 2000 ether);
        vm.expectRevert(expectedError);
        escrow.thaw(users.indexer, 2000 ether);
        vm.stopPrank();
    }

    // Withdraw tests

    function testWithdraw_Tokens() public {
        mint(users.gateway, 1000 ether);
        vm.startPrank(users.gateway);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(users.indexer, 1000 ether);
        escrow.thaw(users.indexer, 100 ether);

        // advance time
        skip(withdrawEscrowThawingPeriod + 1);

        escrow.withdraw(users.indexer);
        vm.stopPrank();

        (uint256 indexerEscrowBalance,,) = escrow.escrowAccounts(users.gateway, users.indexer);
        assertEq(indexerEscrowBalance, 900 ether);
    }

    function testWithdraw_RevertWhen_NotThawing() public {
        mint(users.gateway, 1000 ether);
        vm.startPrank(users.gateway);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(users.indexer, 1000 ether);

        // revert
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.withdraw(users.indexer);
        vm.stopPrank();
    }

    function testWithdraw_RevertWhen_StillThawing() public {
        mint(users.gateway, 1000 ether);
        vm.startPrank(users.gateway);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(users.indexer, 1000 ether);
        escrow.thaw(users.indexer, 100 ether);

        // revert
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowStillThawing(uint256,uint256)", block.timestamp, block.timestamp + withdrawEscrowThawingPeriod);
        vm.expectRevert(expectedError);
        escrow.withdraw(users.indexer);
        vm.stopPrank();
    }

    // Collect tests

    function testCollect() public {
        uint256 amount = 1000 ether;
        createProvision(amount);
        setDelegationFeeCut(0, 100000);

        vm.startPrank(users.gateway);
        escrow.approveCollector(users.verifier, 1000 ether);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(users.indexer, 1000 ether);
        vm.stopPrank();

        uint256 indexerPreviousBalance = token.balanceOf(users.indexer);
        vm.prank(users.verifier);
        escrow.collect(users.gateway, users.indexer, subgraphDataServiceAddress, 100 ether, IGraphPayments.PaymentType.IndexingFees, 3 ether);

        uint256 indexerBalance = token.balanceOf(users.indexer);
        assertEq(indexerBalance - indexerPreviousBalance, 86 ether);
    }

    function testCollect_RevertWhen_CollectorNotAuthorized() public {
        address indexer = address(0xA3);
        uint256 amount = 1000 ether;

        vm.startPrank(users.verifier);
        uint256 dataServiceCut = 30000; // 3%
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowCollectorNotAuthorized(address,address)", users.gateway, users.verifier);
        vm.expectRevert(expectedError);
        escrow.collect(users.gateway, indexer, subgraphDataServiceAddress, amount, IGraphPayments.PaymentType.IndexingFees, dataServiceCut);
        vm.stopPrank();
    }

    function testCollect_RevertWhen_CollectorHasInsufficientAmount() public {
        vm.prank(users.gateway);
        escrow.approveCollector(users.verifier, 100 ether);

        address indexer = address(0xA3);
        uint256 amount = 1000 ether;

        mint(users.gateway, amount);
        vm.startPrank(users.gateway);
        token.approve(address(escrow), amount);
        escrow.deposit(indexer, amount);
        vm.stopPrank();

        vm.startPrank(users.verifier);
        uint256 dataServiceCut = 30 ether;
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowCollectorInsufficientAmount(uint256,uint256)", 100 ether, 1000 ether);
        vm.expectRevert(expectedError);
        escrow.collect(users.gateway, indexer, subgraphDataServiceAddress, 1000 ether, IGraphPayments.PaymentType.IndexingFees, dataServiceCut);
        vm.stopPrank();
    }

    function testCollect_RevertWhen_SenderHasInsufficientAmountInEscrow() public {
        mint(users.gateway, 1000 ether);
        vm.startPrank(users.gateway);
        escrow.approveCollector(users.verifier, 1000 ether);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(users.indexer, 100 ether);
        vm.stopPrank();

        vm.prank(users.verifier);
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowInsufficientAmount(uint256,uint256)", 100 ether, 200 ether);
        vm.expectRevert(expectedError);
        escrow.collect(users.gateway, users.indexer, subgraphDataServiceAddress, 200 ether, IGraphPayments.PaymentType.IndexingFees, 3 ether);
        vm.stopPrank();
    }
}