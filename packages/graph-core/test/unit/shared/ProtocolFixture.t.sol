// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { IController } from "@graphprotocol/interfaces/contracts/contracts/governance/IController.sol";
import { IGraphProxy } from "@graphprotocol/interfaces/contracts/contracts/upgrades/IGraphProxy.sol";
import { IGraphProxyAdmin } from "@graphprotocol/interfaces/contracts/contracts/upgrades/IGraphProxyAdmin.sol";

abstract contract ProtocolFixture is Test {
    address internal governor; // makeAddr("governor"), set in _deployProtocolBase
    IController internal controller;
    IGraphProxyAdmin internal proxyAdmin;

    /// id has the form "Controller.sol:Controller". Deploys the Foundry-compiled contract with CREATE
    /// (honours an active vm.prank). Reverts if the contract is missing or its constructor reverts.
    function _deployPkg(string memory id, bytes memory args) internal returns (address) {
        return vm.deployCode(id, args);
    }

    /// As governor: deploys Controller and GraphProxyAdmin, then controller.setPaused(false).
    /// Must be called with no active prank.
    function _deployProtocolBase() internal {
        governor = makeAddr("governor");
        vm.startPrank(governor);
        controller = IController(_deployPkg("Controller.sol:Controller", ""));
        proxyAdmin = IGraphProxyAdmin(_deployPkg("GraphProxyAdmin.sol:GraphProxyAdmin", ""));
        controller.setPaused(false);
        vm.stopPrank();
    }

    /// As governor: deploys GraphProxy(address(0), proxyAdmin)
    /// proxyAdmin.upgrade(proxy, impl), proxyAdmin.acceptProxyAndCall(impl, proxy, initData).
    /// Must be called with no active prank.
    function _deployBehindProxy(address impl, bytes memory initData) internal returns (address proxy) {
        vm.startPrank(governor);
        proxy = _deployPkg("GraphProxy.sol:GraphProxy", abi.encode(address(0), address(proxyAdmin)));
        proxyAdmin.upgrade(IGraphProxy(proxy), impl);
        proxyAdmin.acceptProxyAndCall(impl, IGraphProxy(proxy), initData);
        vm.stopPrank();
    }

    /// As governor: controller.setContractProxy(keccak256(bytes(name)), addr).
    function _registerContract(string memory name, address addr) internal {
        vm.prank(governor);
        controller.setContractProxy(keccak256(bytes(name)), addr);
    }

    function _stripMetadata(bytes memory code) internal pure returns (bytes memory out) {
        uint256 metadataLength = (uint256(uint8(code[code.length - 2])) << 8) | uint256(uint8(code[code.length - 1]));
        uint256 newLength = code.length - metadataLength - 2;
        out = new bytes(newLength);
        for (uint256 i = 0; i < newLength; i++) out[i] = code[i];
    }
}
