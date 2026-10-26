// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { GraphTokenSharedTest } from "./GraphTokenShared.t.sol";
import { IGraphTokenLike } from "../interfaces/IGraphTokenLike.sol";

contract GraphTokenTest is GraphTokenSharedTest {
    string internal constant GRAPH_TOKEN = string.concat(PKG_ARTIFACTS, "token/GraphToken.sol/GraphToken.json");

    IGraphTokenLike internal grt;

    function setUp() public {
        vm.warp(1_700_000_000);
        _deployProtocolBase();
        vm.prank(governor);
        grt = IGraphTokenLike(_deployArtifact(GRAPH_TOKEN, abi.encode(10_000_000_000 ether)));
        _setUpShared();
    }

    function _token() internal view override returns (IGraphTokenLike) {
        return grt;
    }

    function _salt() internal pure override returns (bytes32) {
        return L1_SALT;
    }
}
