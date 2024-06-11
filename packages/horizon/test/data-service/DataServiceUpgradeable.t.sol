// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { GraphBaseTest } from "../GraphBase.t.sol";
import { DataServiceBaseUpgradeable } from "./implementations/DataServiceBaseUpgradeable.sol";
import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DataServiceUpgradeableTest is GraphBaseTest {
    function test_WhenTheContractIsDeployedWithAValidController() external {
        DataServiceBaseUpgradeable dataService = _deployDataService();

        uint32 delegationRatio = dataService.getDelegationRatio();
        assertEq(delegationRatio, type(uint32).min);

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

    function _deployDataService() internal returns (DataServiceBaseUpgradeable) {
        // Deploy implementation
        address implementation = address(new DataServiceBaseUpgradeable(address(controller)));

        // Deploy proxy
        address proxy = UnsafeUpgrades.deployTransparentProxy(
            implementation,
            users.governor,
            abi.encodeCall(DataServiceBaseUpgradeable.initialize, ())
        );

        return DataServiceBaseUpgradeable(proxy);
    }
}
