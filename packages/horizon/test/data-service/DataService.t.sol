// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { GraphBaseTest } from "../GraphBase.t.sol";
import { DataServiceBase } from "./DataServiceBase.sol";

contract DataService is GraphBaseTest {
    function test_WhenTheContractIsDeployedWithAValidController() external {
        DataServiceBase dataService = _deployDataService();

        (uint32 minDelegationRatio, uint32 maxDelegationRatio) = dataService.getDelegationRatioRange();
        assertEq(minDelegationRatio, type(uint32).min);
        assertEq(maxDelegationRatio, type(uint32).max);

        (uint256 minTokens, uint256 maxTokens) = dataService.getProvisionTokensRange();
        assertEq(minTokens, type(uint256).min);
        assertEq(maxTokens, type(uint256).max);

        (uint32 minVerifierCut, uint32 maxVerifierCut) = dataService.getVerifierCutRange();
        assertEq(minVerifierCut, type(uint32).min);
        assertEq(maxVerifierCut, type(uint32).max);

        (uint64 minThawingPeriod, uint64 maxThawingPeriod) = dataService.getThawingPeriodRange();
        assertEq(minThawingPeriod, type(uint64).min);
        assertEq(maxThawingPeriod, type(uint64).max);
    }

    function _deployDataService() internal returns (DataServiceBase) {
        return new DataServiceBase(address(controller));
    }
}
