// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ProtocolFixture } from "./ProtocolFixture.t.sol";
import { IManagedMock } from "../interfaces/IManagedMock.sol";

abstract contract GraphCoreTest is ProtocolFixture {
    string internal constant MANAGED_MOCK = string.concat(PKG_ARTIFACTS, "tests/ManagedMock.sol/ManagedMock.json");

    address internal implA;
    address internal implB;
    IManagedMock internal managed;

    function setUp() public virtual {
        vm.warp(1_700_000_000);
        _deployProtocolBase();
        implA = _deployArtifact(MANAGED_MOCK, "");
        implB = _deployArtifact(MANAGED_MOCK, "");
        managed = IManagedMock(
            _deployBehindProxy(implA, abi.encodeCall(IManagedMock.initialize, (address(controller))))
        );
    }
}
