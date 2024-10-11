// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IPaymentsEscrow } from "../../../contracts/interfaces/IPaymentsEscrow.sol";
import { GraphBaseTest } from "../../GraphBase.t.sol";

abstract contract PaymentsEscrowSharedTest is GraphBaseTest {

    /*
     * MODIFIERS
     */

    modifier useGateway() {
        vm.startPrank(users.gateway);
        _;
        vm.stopPrank();
    }

    /*
     * HELPERS
     */
    
    function _approveCollector(address _verifier, uint256 _tokens) internal {
        (, address msgSender, ) = vm.readCallers();
        (uint256 beforeAllowance,) = escrow.authorizedCollectors(msgSender, _verifier);
        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.AuthorizedCollector(
            msgSender, // payer
            _verifier, // collector
            _tokens, // addedAllowance
            beforeAllowance + _tokens // newTotalAllowance after the added allowance
        );
        escrow.approveCollector(_verifier, _tokens);
        (uint256 allowance, uint256 thawEndTimestamp) = escrow.authorizedCollectors(msgSender, _verifier);
        assertEq(allowance - beforeAllowance, _tokens);
        assertEq(thawEndTimestamp, 0);
    }

    function _depositTokens(address _collector, address _receiver, uint256 _tokens) internal {
        (, address msgSender, ) = vm.readCallers();
        (uint256 escrowBalanceBefore,,) = escrow.escrowAccounts(msgSender, _collector, _receiver);
        token.approve(address(escrow), _tokens);

        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Deposit(msgSender, _collector, _receiver, _tokens);
        escrow.deposit(_collector, _receiver, _tokens);

        (uint256 escrowBalanceAfter,,) = escrow.escrowAccounts(msgSender, _collector, _receiver);
        assertEq(escrowBalanceAfter - _tokens, escrowBalanceBefore);
    }
}
