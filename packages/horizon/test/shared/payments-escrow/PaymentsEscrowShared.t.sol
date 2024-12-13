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
        
    function _depositToTokens(address _payer, address _collector, address _receiver, uint256 _tokens) internal {
        (uint256 escrowBalanceBefore,,) = escrow.escrowAccounts(_payer, _collector, _receiver);
        token.approve(address(escrow), _tokens);

        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Deposit(_payer, _collector, _receiver, _tokens);
        escrow.depositTo(_payer, _collector, _receiver, _tokens);

        (uint256 escrowBalanceAfter,,) = escrow.escrowAccounts(_payer, _collector, _receiver);
        assertEq(escrowBalanceAfter - _tokens, escrowBalanceBefore);
    }
}
