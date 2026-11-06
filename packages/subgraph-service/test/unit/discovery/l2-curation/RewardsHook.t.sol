// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IManaged } from "@graphprotocol/interfaces/contracts/contracts/governance/IManaged.sol";
import { L2CurationSharedTest } from "./L2CurationShared.t.sol";

contract RewardsManagerRecorder {
    bytes32[] public updates;

    function onSubgraphSignalUpdate(bytes32 subgraphDeploymentID) external returns (uint256) {
        updates.push(subgraphDeploymentID);
        return 0;
    }

    function updatesLength() external view returns (uint256) {
        return updates.length;
    }
}

contract RewardsHookTest is L2CurationSharedTest {
    RewardsManagerRecorder internal recorder;

    function setUp() public override {
        super.setUp();
        recorder = new RewardsManagerRecorder();
        _registerContract("RewardsManager", address(recorder));
        IManaged(address(curation)).syncAllContracts();
    }

    function test_RewardsHook_NotifiedOnMint() public {
        _mint(TOKENS_TO_DEPOSIT);

        assertEq(recorder.updatesLength(), 1);
        assertEq(recorder.updates(0), SUBGRAPH_DEPLOYMENT_ID);
    }

    function test_RewardsHook_NotifiedOnBurn() public {
        uint256 signal = _mint(TOKENS_TO_DEPOSIT);
        assertEq(recorder.updatesLength(), 1);

        vm.prank(curator);
        curation.burn(SUBGRAPH_DEPLOYMENT_ID, signal, 0);

        assertEq(recorder.updatesLength(), 2);
        assertEq(recorder.updates(1), SUBGRAPH_DEPLOYMENT_ID);
    }

    function test_RewardsHook_NotifiedOnMintTaxFree() public {
        vm.prank(address(gns));
        curation.mintTaxFree(SUBGRAPH_DEPLOYMENT_ID, TOKENS_TO_DEPOSIT);

        assertEq(recorder.updatesLength(), 1);
        assertEq(recorder.updates(0), SUBGRAPH_DEPLOYMENT_ID);
    }
}
