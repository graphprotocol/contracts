// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { VmSafe } from "forge-std/Vm.sol";
import { GNSHelpers } from "./shared/GNSHelpers.t.sol";

contract SetupTest is GNSHelpers {
    function test_Setup_Wired() public view {
        assertEq(nft.minter(), address(gns));
        assertEq(curation.subgraphService(), subgraphService);
        assertEq(gns.counterpartGNSAddress(), l1GNS);
    }

    function test_Setup_PublishNewSubgraph() public {
        _publishNewSubgraph(me, DEPLOYMENT_ID_0);
    }

    function test_Setup_FoundryL2GNSMatchesHardhat() public {
        vm.skip(vm.isContext(VmSafe.ForgeContext.Coverage));
        string memory json = vm.readFile("artifacts/contracts/l2/discovery/L2GNS.sol/L2GNS.json");
        bytes memory hardhat = _stripMetadata(vm.parseJsonBytes(json, ".bytecode"));
        bytes memory foundry = _stripMetadata(vm.getCode(L2_GNS));
        assertGt(hardhat.length, 0);
        assertEq(foundry, hardhat);
    }
}
