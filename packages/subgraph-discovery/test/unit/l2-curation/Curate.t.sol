// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { L2CurationSharedTest } from "./L2CurationShared.t.sol";
import { IL2CurationLike } from "../interfaces/IL2CurationLike.sol";

contract CurateTest is L2CurationSharedTest {
    function test_Curate_RevertWhen_BelowMinimumDeposit() public {
        // Set the minimum to a value greater than 1 so that we can test
        vm.prank(governor);
        curation.setMinimumCurationDeposit(2);
        uint256 tokensToDeposit = curation.minimumCurationDeposit() - 1;

        vm.expectRevert(bytes("Curation deposit is below minimum required"));
        vm.prank(curator);
        curation.mint(SUBGRAPH_DEPLOYMENT_ID, tokensToDeposit, 0);
    }

    function test_Curate_DepositOnSubgraphDeployment() public {
        _shouldMint(curation.minimumCurationDeposit(), SIGNAL_AMOUNT_FOR_MINIMUM_CURATION);
    }

    function test_Curate_SignalAccordingToBondingCurve() public {
        _shouldMint(1000 ether, SIGNAL_AMOUNT_FOR_1000_TOKENS);
    }

    function test_Curate_SignalAccordingToBondingCurveWithCurationTax() public {
        vm.prank(governor);
        curation.setCurationTaxPercentage(50_000); // 5%

        (uint256 expectedSignal, ) = curation.tokensToSignal(SUBGRAPH_DEPLOYMENT_ID, 1000 ether);
        _shouldMint(1000 ether, expectedSignal);
    }

    function test_Curate_RevertWhen_OverSlippage() public {
        vm.expectRevert(bytes("Slippage protection"));
        vm.prank(curator);
        curation.mint(SUBGRAPH_DEPLOYMENT_ID, 1000 ether, SIGNAL_AMOUNT_FOR_1000_TOKENS + 1);
    }

    function test_Curate_PaysMinimumOneWeiTaxOnSmallDeposits() public {
        vm.startPrank(governor);
        curation.setMinimumCurationDeposit(1);
        curation.setCurationTaxPercentage(10_000); // 1%
        vm.stopPrank();

        // Deposit a small amount where tax would be less than 1 wei
        uint256 tokensToDeposit = 99;
        uint256 expectedTokens = 98;
        uint256 expectedSignal = 98;
        uint256 expectedTax = 1;

        vm.expectEmit(address(curation));
        emit IL2CurationLike.Signalled(curator, SUBGRAPH_DEPLOYMENT_ID, tokensToDeposit, expectedSignal, expectedTax);
        vm.prank(curator);
        curation.mint(SUBGRAPH_DEPLOYMENT_ID, tokensToDeposit, expectedSignal);

        vm.expectEmit(address(curation));
        emit IL2CurationLike.Burned(curator, SUBGRAPH_DEPLOYMENT_ID, expectedTokens, expectedSignal);
        vm.prank(curator);
        curation.burn(SUBGRAPH_DEPLOYMENT_ID, expectedSignal, expectedTokens);
    }
}
