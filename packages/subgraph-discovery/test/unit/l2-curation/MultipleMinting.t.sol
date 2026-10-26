// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { L2CurationSharedTest } from "./L2CurationShared.t.sol";

contract MultipleMintingTest is L2CurationSharedTest {
    function _tokensToDepositMany() private pure returns (uint256[8] memory) {
        return
            [
                uint256(1000 ether), // should mint if we start with number above minimum deposit
                1000 ether, // every time it should mint the same GCS due to the bonding curve
                1000 ether,
                1000 ether,
                2000 ether,
                2000 ether,
                123 ether,
                1 ether // should mint below minimum deposit
            ];
    }

    /// Linear bonding curve computed independently of the contract
    function _calcLinearBondingCurve(
        uint256 supply,
        uint256 reserveBalance,
        uint256 depositAmount
    ) private view returns (uint256) {
        // Handle the initialization of the bonding curve
        if (supply == 0) {
            uint256 minDeposit = curation.minimumCurationDeposit();
            require(depositAmount >= minDeposit, "deposit must be above minimum");
            uint256 minSupply = SIGNAL_AMOUNT_FOR_MINIMUM_CURATION;
            return _calcLinearBondingCurve(minSupply, minDeposit, depositAmount - minDeposit) + minSupply;
        }
        return (supply * depositAmount) / reserveBalance;
    }

    function test_MultipleMinting_SameSignalDueToFlatBondingCurve() public {
        uint256[8] memory tokensToDepositMany = _tokensToDepositMany();
        for (uint256 i = 0; i < tokensToDepositMany.length; i++) {
            uint256 tokensToDeposit = tokensToDepositMany[i];
            uint256 expectedSignal = _calcLinearBondingCurve(
                curation.getCurationPoolSignal(SUBGRAPH_DEPLOYMENT_ID),
                curation.getCurationPoolTokens(SUBGRAPH_DEPLOYMENT_ID),
                tokensToDeposit
            );
            // SIGNAL_PER_MINIMUM_DEPOSIT should always give the same ratio
            assertEq(tokensToDeposit / expectedSignal, 1);

            assertEq(_mint(tokensToDeposit), expectedSignal);
        }
    }

    function test_MultipleMinting_DifferentRatioBetweenGRTAndSignal() public {
        // Setup edge case with 1 GRT = 1 wei signal
        vm.prank(governor);
        curation.setMinimumCurationDeposit(1 ether);

        uint256[8] memory tokensToDepositMany = _tokensToDepositMany();
        for (uint256 i = 0; i < tokensToDepositMany.length; i++) {
            uint256 tokensToDeposit = tokensToDepositMany[i];
            // 1 GRT : 1 wei signal ratio
            assertEq(tokensToDeposit, _mint(tokensToDeposit) * 1 ether);
        }
    }
}
