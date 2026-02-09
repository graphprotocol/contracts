// SPDX-License-Identifier: MIT
pragma solidity 0.8.27 || 0.8.33;

import { Test } from "forge-std/Test.sol";

import { ControllerMock } from "../../../contracts/mocks/ControllerMock.sol";

contract PartialControllerMock is ControllerMock, Test {
    struct Entry {
        string name;
        address addr;
    }

    address private _invalidContractAddress;

    Entry[] private _contracts;

    constructor(Entry[] memory contracts) ControllerMock(address(0)) {
        for (uint256 i = 0; i < contracts.length; i++) {
            _contracts.push(Entry({ name: contracts[i].name, addr: contracts[i].addr }));
        }
        _invalidContractAddress = makeAddr("invalidContractAddress");
    }

    function getContractProxy(bytes32 data) external view override returns (address) {
        for (uint256 i = 0; i < _contracts.length; i++) {
            if (keccak256(abi.encodePacked(_contracts[i].name)) == data) {
                return _contracts[i].addr;
            }
        }
        return _invalidContractAddress;
    }
}
