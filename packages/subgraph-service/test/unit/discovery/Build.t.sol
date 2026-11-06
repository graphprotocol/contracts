// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { VmSafe } from "forge-std/Vm.sol";
import { IGraphProxy } from "@graphprotocol/interfaces/contracts/contracts/upgrades/IGraphProxy.sol";

import { DiscoveryTest } from "./shared/DiscoveryTest.t.sol";

/// @notice Pins which L2Curation and L2GNS builds the suite runs: Foundry's build must match the published
/// Hardhat artifact, and the suite's implementations must be the build that was requested (PRE_PORT).
/// Also pins the initializer state that InitializableV3 keeps in ordinary storage slots.
contract BuildTest is DiscoveryTest {
    string internal constant L2_CURATION_ID = "L2Curation.sol:L2Curation";
    string internal constant L2_GNS_ID = "L2GNS.sol:L2GNS";
    string internal constant L2_CURATION_HARDHAT_ARTIFACT =
        "build/contracts/contracts/l2/curation/L2Curation.sol/L2Curation.json";
    string internal constant L2_GNS_HARDHAT_ARTIFACT = "build/contracts/contracts/l2/discovery/L2GNS.sol/L2GNS.json";

    function test_Build_FoundryMatchesHardhat() public {
        vm.skip(_isPrePort() || vm.isContext(VmSafe.ForgeContext.Coverage));

        _assertFoundryMatchesHardhat(L2_CURATION_ID, L2_CURATION_HARDHAT_ARTIFACT);
        _assertFoundryMatchesHardhat(L2_GNS_ID, L2_GNS_HARDHAT_ARTIFACT);
    }

    /// Runtime code embeds immutables, so builds are compared by the code hash of a reference deployment.
    function test_Build_DeploysRequestedBuild() public {
        _assertDeploysRequestedBuild(L2_CURATION_ID, L2_CURATION_FIXTURE, address(curation));
        _assertDeploysRequestedBuild(L2_GNS_ID, L2_GNS_FIXTURE, address(gns));
    }

    // -- InitializableV3 --

    /// `_initialized` (offset 0) is true and `_initializing` (offset 1) false; subgraphService packs after them.
    function test_L2Curation_InitializedFlagsInSlot16() public view {
        bytes32 slot16 = vm.load(address(curation), bytes32(uint256(16)));
        assertEq(uint16(uint256(slot16)), 0x0001);
    }

    function test_L2Curation_RevertWhen_InitializedTwice() public {
        address impl = proxyAdmin.getProxyImplementation(IGraphProxy(address(curation)));
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        vm.prank(impl);
        curation.initialize(address(controller), curationTokenMaster, 0, 1);
    }

    function test_L2GNS_RevertWhen_InitializedTwice() public {
        address impl = proxyAdmin.getProxyImplementation(IGraphProxy(address(gns)));
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        vm.prank(impl);
        gns.initialize(address(controller), address(nft));
    }

    function _assertFoundryMatchesHardhat(string memory id, string memory artifact) internal view {
        bytes memory foundry = _stripMetadata(vm.getCode(id));
        bytes memory hardhat = _stripMetadata(vm.parseJsonBytes(vm.readFile(artifact), ".bytecode"));
        assertEq(foundry, hardhat, id);
    }

    function _assertDeploysRequestedBuild(string memory id, string memory fixture, address proxy) internal {
        bytes32 prePortHash = _deployArtifact(fixture, "").codehash;
        bytes32 portHash = deployCode(id).codehash;
        assertTrue(prePortHash != portHash, "builds are identical");

        bytes32 implHash = proxyAdmin.getProxyImplementation(IGraphProxy(proxy)).codehash;
        assertEq(implHash, _isPrePort() ? prePortHash : portHash, id);
        assertTrue(implHash != (_isPrePort() ? portHash : prePortHash), id);
    }

    /// Drops the trailing CBOR metadata, whose length is the code's last two bytes.
    function _stripMetadata(bytes memory code) internal pure returns (bytes memory stripped) {
        uint256 len = (uint256(uint8(code[code.length - 2])) << 8) | uint8(code[code.length - 1]);
        stripped = new bytes(code.length - len - 2);
        for (uint256 i = 0; i < stripped.length; ++i) stripped[i] = code[i];
    }
}
