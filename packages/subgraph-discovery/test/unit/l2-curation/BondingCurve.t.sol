// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { L2CurationSharedTest } from "./L2CurationShared.t.sol";

contract BondingCurveTest is L2CurationSharedTest {
    function test_BondingCurve_RevertWhen_SignalToTokensNotCurated() public {
        vm.expectRevert(bytes("Subgraph deployment must be curated to perform calculations"));
        curation.signalToTokens(SUBGRAPH_DEPLOYMENT_ID, 100 ether);
    }

    function test_BondingCurve_ConvertSignalToTokens() public {
        _mint(CURATOR_TOKENS);

        uint256 signal = curation.getCurationPoolSignal(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(curation.signalToTokens(SUBGRAPH_DEPLOYMENT_ID, signal), CURATOR_TOKENS);
    }

    function test_BondingCurve_ConvertSignalToTokensWithCurationTax() public {
        uint32 curationTaxPercentage = 50_000; // 5%
        vm.prank(governor);
        curation.setCurationTaxPercentage(curationTaxPercentage);

        uint256 expectedCurationTax = (CURATOR_TOKENS * curationTaxPercentage) / MAX_PPM;
        (, uint256 curationTax) = curation.tokensToSignal(SUBGRAPH_DEPLOYMENT_ID, CURATOR_TOKENS);
        _mint(CURATOR_TOKENS);

        uint256 signal = curation.getCurationPoolSignal(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(curation.signalToTokens(SUBGRAPH_DEPLOYMENT_ID, signal), CURATOR_TOKENS - expectedCurationTax);
        assertEq(expectedCurationTax, curationTax);
    }

    function test_BondingCurve_ConvertTokensToSignal() public view {
        (uint256 signal, ) = curation.tokensToSignal(SUBGRAPH_DEPLOYMENT_ID, 1000 ether);
        assertEq(signal, SIGNAL_AMOUNT_FOR_1000_TOKENS);
    }

    function test_BondingCurve_RevertWhen_ConvertTokensToSignalBelowMinimum() public {
        vm.expectRevert(bytes("Curation deposit is below minimum required"));
        curation.tokensToSignal(keccak256("nonCuratedSubgraphDeploymentID"), 0);
    }

    function test_BondingCurve_TokensToSignalToTokensNoTax() public {
        _mint(TOKENS_TO_DEPOSIT);

        // Flat curve: depositing tokens and redeeming the resulting signal returns the same tokens
        assertEq(curation.tokensToSignalToTokensNoTax(SUBGRAPH_DEPLOYMENT_ID, TOKENS_TO_DEPOSIT), TOKENS_TO_DEPOSIT);
    }
}
