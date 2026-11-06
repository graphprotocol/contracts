// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { L2CurationSharedTest } from "./L2CurationShared.t.sol";

contract BurnTest is L2CurationSharedTest {
    function setUp() public override {
        super.setUp();
        _mint(TOKENS_TO_DEPOSIT);
    }

    function test_Burn_RevertWhen_MoreThanOwned() public {
        vm.expectRevert(bytes("Cannot burn more signal than you own"));
        vm.prank(me);
        curation.burn(SUBGRAPH_DEPLOYMENT_ID, 1 ether, 0);
    }

    function test_Burn_RevertWhen_ZeroSignal() public {
        vm.expectRevert(bytes("Cannot burn zero signal"));
        vm.prank(me);
        curation.burn(SUBGRAPH_DEPLOYMENT_ID, 0, 0);
    }

    function test_Burn_Partially() public {
        _shouldBurn(1 ether, 1 ether);
    }

    function test_Burn_Fully() public {
        uint256 signalToRedeem = curation.getCuratorSignal(curator, SUBGRAPH_DEPLOYMENT_ID);
        _shouldBurn(signalToRedeem, TOKENS_TO_DEPOSIT);
    }

    function test_Burn_BackBelowMinimumDeposit() public {
        // Set the minimum to a value greater than 1 so that we can test
        vm.prank(governor);
        curation.setMinimumCurationDeposit(1 ether);

        // Redeem "almost" all signal
        uint256 signal = curation.getCuratorSignal(curator, SUBGRAPH_DEPLOYMENT_ID);
        uint256 signalToRedeem = signal - 0.000001 ether;
        uint256 expectedTokens = curation.signalToTokens(SUBGRAPH_DEPLOYMENT_ID, signalToRedeem);
        _shouldBurn(signalToRedeem, expectedTokens);

        // The pool should have less tokens than required by minimumCurationDeposit
        (uint256 poolTokens, , ) = curation.pools(SUBGRAPH_DEPLOYMENT_ID);
        assertLt(poolTokens, curation.minimumCurationDeposit());

        // Should be able to deposit more after being under minimumCurationDeposit
        (uint256 expectedSignal, ) = curation.tokensToSignal(SUBGRAPH_DEPLOYMENT_ID, 1 ether);
        _shouldMint(1 ether, expectedSignal);
    }

    function test_Burn_RevertWhen_OverSlippage() public {
        uint256 signalToRedeem = curation.getCuratorSignal(curator, SUBGRAPH_DEPLOYMENT_ID);

        vm.expectRevert(bytes("Slippage protection"));
        vm.prank(curator);
        curation.burn(SUBGRAPH_DEPLOYMENT_ID, signalToRedeem, TOKENS_TO_DEPOSIT + 1);
    }

    function test_Burn_DoesNotRedeployCurationTokenWhenSignalReset() public {
        (, , address beforeGcs) = curation.pools(SUBGRAPH_DEPLOYMENT_ID);

        // Burn all the signal
        uint256 signalToRedeem = curation.getCuratorSignal(curator, SUBGRAPH_DEPLOYMENT_ID);
        _shouldBurn(signalToRedeem, TOKENS_TO_DEPOSIT);

        // Mint again on the same subgraph
        _mint(TOKENS_TO_DEPOSIT);

        (, , address afterGcs) = curation.pools(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(afterGcs, beforeGcs);
    }
}
