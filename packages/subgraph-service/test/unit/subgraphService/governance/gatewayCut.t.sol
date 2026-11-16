// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SubgraphServiceGovernanceGatewayCutTest is SubgraphServiceTest {
    address internal gatewayCutDestination = makeAddr("gatewayCutDestination");

    /*
     * TESTS: setGatewayCutDestination
     */

    function test_Governance_SetGatewayCutDestination(address destination) public useGovernor {
        vm.assume(destination != address(0) && destination != address(subgraphService));

        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.GatewayCutDestinationSet(destination);
        subgraphService.setGatewayCutDestination(destination);

        assertEq(subgraphService.gatewayCutDestination(), destination);
    }

    function test_Governance_SetGatewayCutDestination_RevertWhen_ZeroAddress() public useGovernor {
        vm.expectRevert(
            abi.encodeWithSelector(ISubgraphService.SubgraphServiceInvalidGatewayCutDestination.selector, address(0))
        );
        subgraphService.setGatewayCutDestination(address(0));
    }

    function test_Governance_SetGatewayCutDestination_RevertWhen_SubgraphService() public useGovernor {
        vm.expectRevert(
            abi.encodeWithSelector(
                ISubgraphService.SubgraphServiceInvalidGatewayCutDestination.selector,
                address(subgraphService)
            )
        );
        subgraphService.setGatewayCutDestination(address(subgraphService));
    }

    function test_Governance_SetGatewayCutDestination_RevertWhen_NotGovernor() public useIndexer {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.indexer));
        subgraphService.setGatewayCutDestination(gatewayCutDestination);
    }

    /*
     * TESTS: setGatewayCut
     */

    function test_Governance_SetGatewayCut(uint256 gatewayCut) public useGovernor {
        gatewayCut = bound(gatewayCut, 0, MAX_PPM - subgraphService.curationFeesCut());
        subgraphService.setGatewayCutDestination(gatewayCutDestination);

        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.GatewayCutSet(gatewayCut);
        subgraphService.setGatewayCut(gatewayCut);

        assertEq(subgraphService.gatewayCut(), gatewayCut);
    }

    function test_Governance_SetGatewayCut_ToZeroWithoutDestination() public useGovernor {
        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.GatewayCutSet(0);
        subgraphService.setGatewayCut(0);

        assertEq(subgraphService.gatewayCut(), 0);
    }

    function test_Governance_SetGatewayCut_RevertWhen_AboveCurationCutHeadroom(uint256 gatewayCut) public useGovernor {
        vm.assume(gatewayCut > MAX_PPM - subgraphService.curationFeesCut());
        subgraphService.setGatewayCutDestination(gatewayCutDestination);

        vm.expectRevert(abi.encodeWithSelector(ISubgraphService.SubgraphServiceInvalidGatewayCut.selector, gatewayCut));
        subgraphService.setGatewayCut(gatewayCut);
    }

    function test_Governance_SetGatewayCut_RevertWhen_NoDestination(uint256 gatewayCut) public useGovernor {
        gatewayCut = bound(gatewayCut, 1, MAX_PPM - subgraphService.curationFeesCut());

        vm.expectRevert(
            abi.encodeWithSelector(ISubgraphService.SubgraphServiceInvalidGatewayCutDestination.selector, address(0))
        );
        subgraphService.setGatewayCut(gatewayCut);
    }

    function test_Governance_SetGatewayCut_RevertWhen_NotGovernor() public useIndexer {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.indexer));
        subgraphService.setGatewayCut(100_000);
    }

    /*
     * TESTS: setCurationCut with a gateway cut set
     */

    function test_Governance_SetCurationCut_RevertWhen_AboveGatewayCutHeadroom(
        uint256 gatewayCut,
        uint256 curationCut
    ) public useGovernor {
        gatewayCut = bound(gatewayCut, 1, MAX_PPM - subgraphService.curationFeesCut());
        subgraphService.setGatewayCutDestination(gatewayCutDestination);
        subgraphService.setGatewayCut(gatewayCut);
        curationCut = bound(curationCut, MAX_PPM - gatewayCut + 1, MAX_PPM);

        vm.expectRevert(
            abi.encodeWithSelector(ISubgraphService.SubgraphServiceInvalidCurationCut.selector, curationCut)
        );
        subgraphService.setCurationCut(curationCut);
    }

    function test_Governance_SetCurationCut_UpToGatewayCutHeadroom(
        uint256 gatewayCut,
        uint256 curationCut
    ) public useGovernor {
        gatewayCut = bound(gatewayCut, 1, MAX_PPM - subgraphService.curationFeesCut());
        subgraphService.setGatewayCutDestination(gatewayCutDestination);
        subgraphService.setGatewayCut(gatewayCut);
        curationCut = bound(curationCut, 0, MAX_PPM - gatewayCut);

        subgraphService.setCurationCut(curationCut);

        assertEq(subgraphService.curationFeesCut(), curationCut);
    }
}
