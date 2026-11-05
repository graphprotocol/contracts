// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { IController } from "@graphprotocol/interfaces/contracts/contracts/governance/IController.sol";
import { IGraphProxy } from "@graphprotocol/interfaces/contracts/contracts/upgrades/IGraphProxy.sol";
import { IGraphProxyAdmin } from "@graphprotocol/interfaces/contracts/contracts/upgrades/IGraphProxyAdmin.sol";

abstract contract ProtocolFixture is Test {
    string internal constant CORE_ARTIFACTS = "node_modules/@graphprotocol/graph-core/artifacts/contracts/";

    address internal governor; // makeAddr("governor"), set in _deployProtocolBase
    IController internal controller;
    IGraphProxyAdmin internal proxyAdmin;

    /// path is a full artifact path, e.g. string.concat(CORE_ARTIFACTS, "governance/Controller.sol/Controller.json").
    /// Deploys `.bytecode ++ args` with CREATE (honours an active vm.prank).
    /// Reverts "artifact needs linking" if `.linkReferences` has any key (vm.parseJsonKeys),
    /// and "artifact deploy failed" if CREATE returns 0.
    function _deployArtifact(string memory path, bytes memory args) internal returns (address deployed) {
        string memory json = vm.readFile(path);
        require(vm.parseJsonKeys(json, ".linkReferences").length == 0, "artifact needs linking");
        bytes memory code = bytes.concat(vm.parseJsonBytes(json, ".bytecode"), args);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            deployed := create(0, add(code, 0x20), mload(code))
        }
        require(deployed != address(0), "artifact deploy failed");
    }

    /// True when the suite runs against the pre-port 0.7.6 fixtures (PRE_PORT=true) instead of the 0.8 build.
    function _isPrePort() internal view returns (bool) {
        return vm.envOr("PRE_PORT", false);
    }

    /// Deploys a ported contract: the 0.8 build `id` (e.g. "RewardsManager.sol:RewardsManager") with deployCode,
    /// or, when `_isPrePort()`, the pre-port Hardhat artifact at `fixture`.
    function _deployPorted(string memory id, string memory fixture) internal returns (address) {
        return _isPrePort() ? _deployArtifact(fixture, "") : deployCode(id);
    }

    /// As governor: deploys Controller and GraphProxyAdmin from CORE_ARTIFACTS, then controller.setPaused(false).
    /// Must be called with no active prank.
    function _deployProtocolBase() internal {
        governor = makeAddr("governor");
        vm.startPrank(governor);
        controller = IController(
            _deployArtifact(string.concat(CORE_ARTIFACTS, "governance/Controller.sol/Controller.json"), "")
        );
        proxyAdmin = IGraphProxyAdmin(
            _deployArtifact(string.concat(CORE_ARTIFACTS, "upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json"), "")
        );
        controller.setPaused(false);
        vm.stopPrank();
    }

    /// As governor: deploys GraphProxy(address(0), proxyAdmin) from CORE_ARTIFACTS,
    /// proxyAdmin.upgrade(proxy, impl), proxyAdmin.acceptProxyAndCall(impl, proxy, initData).
    /// Must be called with no active prank.
    function _deployBehindProxy(address impl, bytes memory initData) internal returns (address proxy) {
        vm.startPrank(governor);
        proxy = _deployArtifact(
            string.concat(CORE_ARTIFACTS, "upgrades/GraphProxy.sol/GraphProxy.json"),
            abi.encode(address(0), address(proxyAdmin))
        );
        proxyAdmin.upgrade(IGraphProxy(proxy), impl);
        proxyAdmin.acceptProxyAndCall(impl, IGraphProxy(proxy), initData);
        vm.stopPrank();
    }

    /// As governor: controller.setContractProxy(keccak256(bytes(name)), addr).
    function _registerContract(string memory name, address addr) internal {
        vm.prank(governor);
        controller.setContractProxy(keccak256(bytes(name)), addr);
    }
}
