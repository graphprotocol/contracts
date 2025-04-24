// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import { GraphBaseTest } from "../../GraphBase.t.sol";
import { DataServiceImpPausableUpgradeable } from "../implementations/DataServiceImpPausableUpgradeable.sol";
import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { PPMMath } from "./../../../contracts/libraries/PPMMath.sol";

contract DataServicePausableUpgradeableTest is GraphBaseTest {
    function test_WhenTheContractIsDeployed() external {
        (
            DataServiceImpPausableUpgradeable dataService,
            DataServiceImpPausableUpgradeable implementation
        ) = _deployDataService();

        // via proxy - ensure that the proxy was initialized correctly
        // these calls validate proxy storage was correctly initialized
        uint32 delegationRatio = dataService.getDelegationRatio();
        assertEq(delegationRatio, type(uint32).max);

        (uint256 minTokens, uint256 maxTokens) = dataService.getProvisionTokensRange();
        assertEq(minTokens, type(uint256).min);
        assertEq(maxTokens, type(uint256).max);

        (uint32 minVerifierCut, uint32 maxVerifierCut) = dataService.getVerifierCutRange();
        assertEq(minVerifierCut, type(uint32).min);
        assertEq(maxVerifierCut, uint32(PPMMath.MAX_PPM));

        (uint64 minThawingPeriod, uint64 maxThawingPeriod) = dataService.getThawingPeriodRange();
        assertEq(minThawingPeriod, type(uint64).min);
        assertEq(maxThawingPeriod, type(uint64).max);

        // this ensures that implementation immutables were correctly initialized
        // and they can be read via the proxy
        assertEq(implementation.controller(), address(controller));
        assertEq(dataService.controller(), address(controller));
    }

    function _deployDataService()
        internal
        returns (DataServiceImpPausableUpgradeable, DataServiceImpPausableUpgradeable)
    {
        // Deploy implementation
        address implementation = address(new DataServiceImpPausableUpgradeable(address(controller)));

        // Deploy proxy
        address proxy = UnsafeUpgrades.deployTransparentProxy(
            implementation,
            users.governor,
            abi.encodeCall(DataServiceImpPausableUpgradeable.initialize, ())
        );

        return (DataServiceImpPausableUpgradeable(proxy), DataServiceImpPausableUpgradeable(implementation));
    }
}
