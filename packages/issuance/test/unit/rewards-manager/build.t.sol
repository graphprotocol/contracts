// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { VmSafe } from "forge-std/Vm.sol";
import { IGraphProxy } from "@graphprotocol/interfaces/contracts/contracts/upgrades/IGraphProxy.sol";

import { RewardsManagerSharedTest } from "./shared.t.sol";

/// @notice Pins which RewardsManager build the suite runs: Foundry's build must match the published
/// Hardhat artifact, and the suite's implementation must be the build that was requested (PRE_PORT).
contract RewardsManagerBuildTest is RewardsManagerSharedTest {
    string internal constant RM_ID = "RewardsManager.sol:RewardsManager";
    string internal constant RM_HARDHAT_ARTIFACT = "artifacts/contracts/rewards/RewardsManager.sol/RewardsManager.json";

    function test_Build_FoundryMatchesHardhat() public {
        vm.skip(_isPrePort() || vm.isContext(VmSafe.ForgeContext.Coverage));

        bytes memory foundry = _stripMetadata(vm.getCode(RM_ID));
        bytes memory hardhat = _stripMetadata(vm.parseJsonBytes(vm.readFile(RM_HARDHAT_ARTIFACT), ".bytecode"));
        assertEq(foundry, hardhat);
    }

    /// Runtime code embeds Managed's immutables, so builds are compared by the code hash of a reference deployment.
    function test_Build_DeploysRequestedBuild() public {
        bytes32 prePortHash = _deployArtifact(RM_FIXTURE, "").codehash;
        bytes32 portHash = deployCode(RM_ID).codehash;
        assertTrue(prePortHash != portHash, "builds are identical");

        bytes32 implHash = proxyAdmin.getProxyImplementation(IGraphProxy(address(rm))).codehash;
        assertEq(implHash, _isPrePort() ? prePortHash : portHash);
        assertTrue(implHash != (_isPrePort() ? portHash : prePortHash));
    }

    /// Drops the trailing CBOR metadata, whose length is the code's last two bytes.
    function _stripMetadata(bytes memory code) internal pure returns (bytes memory stripped) {
        uint256 len = (uint256(uint8(code[code.length - 2])) << 8) | uint8(code[code.length - 1]);
        stripped = new bytes(code.length - len - 2);
        for (uint256 i = 0; i < stripped.length; ++i) stripped[i] = code[i];
    }
}
