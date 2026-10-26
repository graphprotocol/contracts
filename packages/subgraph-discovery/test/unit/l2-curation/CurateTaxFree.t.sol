// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { L2CurationSharedTest } from "./L2CurationShared.t.sol";

contract CurateTaxFreeTest is L2CurationSharedTest {
    function test_CurateTaxFree_RevertWhen_NotGNS() public {
        uint256 tokensToDeposit = curation.minimumCurationDeposit();

        vm.expectRevert(bytes("Only the GNS can call this"));
        vm.prank(curator);
        curation.mintTaxFree(SUBGRAPH_DEPLOYMENT_ID, tokensToDeposit);
    }

    function test_CurateTaxFree_RevertWhen_BelowMinimumDeposit() public {
        // Set the minimum to a value greater than 1 so that we can test
        vm.prank(governor);
        curation.setMinimumCurationDeposit(2);
        uint256 tokensToDeposit = curation.minimumCurationDeposit() - 1;

        vm.expectRevert(bytes("Curation deposit is below minimum required"));
        vm.prank(address(gns));
        curation.mintTaxFree(SUBGRAPH_DEPLOYMENT_ID, tokensToDeposit);
    }

    function test_CurateTaxFree_DepositOnSubgraphDeployment() public {
        _shouldMintTaxFree(curation.minimumCurationDeposit(), SIGNAL_AMOUNT_FOR_MINIMUM_CURATION);
    }

    function test_CurateTaxFree_SignalAccordingToBondingCurve() public {
        _shouldMintTaxFree(1000 ether, SIGNAL_AMOUNT_FOR_1000_TOKENS);
    }

    function test_CurateTaxFree_SignalAccordingToBondingCurveWithZeroTax() public {
        vm.prank(governor);
        curation.setCurationTaxPercentage(50_000); // 5%

        uint256 expectedSignal = curation.tokensToSignalNoTax(SUBGRAPH_DEPLOYMENT_ID, 1000 ether);
        _shouldMintTaxFree(1000 ether, expectedSignal);
    }
}
