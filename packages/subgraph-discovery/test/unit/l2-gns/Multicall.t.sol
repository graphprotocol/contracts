// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { GNSHelpers } from "../shared/GNSHelpers.t.sol";
import { IL2GNSLike } from "../interfaces/IL2GNSLike.sol";

contract MulticallTest is GNSHelpers {
    function test_GNS_Multicall() public {
        uint256 tokens = 1000 ether;
        uint256 subgraphId = uint256(keccak256(abi.encodePacked(me, gns.nextAccountSeqID(me), block.chainid)));
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(
            IL2GNSLike.publishNewSubgraph,
            (DEPLOYMENT_ID_0, _versionMetadata(DEPLOYMENT_ID_0), _subgraphMetadata(DEPLOYMENT_ID_0))
        );
        calls[1] = abi.encodeCall(IL2GNSLike.mintSignal, (subgraphId, tokens, 0));

        vm.startPrank(me);
        grt.approve(address(gns), tokens);
        bytes[] memory results = gns.multicall(calls);
        vm.stopPrank();

        assertEq(results.length, 2);
        assertEq(gns.ownerOf(subgraphId), me);
        assertEq(_subgraph(subgraphId).subgraphDeploymentID, DEPLOYMENT_ID_0);
        uint256 nSignal = _subgraph(subgraphId).nSignal;
        assertGt(nSignal, 0);
        assertEq(gns.getCuratorSignal(subgraphId, me), nSignal);
        // Curation tax is zero
        assertEq(curation.getCurationPoolTokens(DEPLOYMENT_ID_0), tokens);
    }
}
