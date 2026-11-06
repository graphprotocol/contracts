// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import { GraphProxy } from "@graphprotocol/graph-core/contracts/upgrades/GraphProxy.sol";
import { GraphUpgradeable } from "@graphprotocol/graph-core/contracts/upgrades/GraphUpgradeable.sol";
import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";

import { FullStackHarness } from "./FullStackHarness.t.sol";

/// @dev Minimal handle for the real RewardsManager's governor-only admin surface.
///      The full ABI lives in the artifact loaded as bytecode.
interface IRealRewardsManager {
    function initialize(address controller) external;
    function setIssuancePerBlock(uint256 issuancePerBlock) external;
    function setSubgraphService(address subgraphService) external;
}

/// @title RealRewardsHarness
/// @notice FullStackHarness variant that wires the **real production RewardsManager**
///         in place of `MockRewardsManager`, with zero other changes to the
///         stack. Any test that extends this instead of FullStackHarness exercises the genuine
///         reward-accounting math, rather than a mock whose simplified `takeRewards` cannot
///         surface over-allocation double-collection in the resize path.
///
/// The RewardsManager is loaded as precompiled bytecode from issuance's hardhat artifact, so the
/// harness runs the production build. The artifact must exist: build the issuance package first.
abstract contract RealRewardsHarness is FullStackHarness {
    string internal constant RM_ARTIFACT =
        "node_modules/@graphprotocol/issuance/artifacts/contracts/rewards/RewardsManager.sol/RewardsManager.json";
    uint256 internal constant RM_ISSUANCE_PER_BLOCK = 100 ether;
    uint256 internal constant RM_CURATION_SIGNAL = 1_000_000 ether;

    /// @notice Typed handle to the real RewardsManager proxy.
    IRewardsManager internal realRewardsManager;

    /// @dev Swap in the real bytecode-loaded RewardsManager. Self-manages pranks.
    function _deployRewardsManager() internal override returns (address) {
        require(vm.exists(RM_ARTIFACT), "RewardsManager artifact missing: build issuance");

        bytes memory rmBytecode = vm.parseJsonBytes(vm.readFile(RM_ARTIFACT), ".bytecode");
        address rmImpl;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            rmImpl := create(0, add(rmBytecode, 0x20), mload(rmBytecode))
        }
        require(rmImpl != address(0), "real RM deploy failed");

        vm.startPrank(governor);
        GraphProxy rmProxy = new GraphProxy(address(0), address(proxyAdmin));
        proxyAdmin.upgrade(rmProxy, rmImpl);
        proxyAdmin.acceptProxyAndCall(
            GraphUpgradeable(rmImpl),
            rmProxy,
            abi.encodeCall(IRealRewardsManager.initialize, (address(controller)))
        );
        vm.stopPrank();

        realRewardsManager = IRewardsManager(address(rmProxy));
        return address(rmProxy);
    }

    function setUp() public virtual override {
        super.setUp();

        // Real-RM config that the mock doesn't need: authorize SubgraphService as the rewards
        // issuer, set issuance, and provide curation signal so rewards accrue (MockCuration has
        // no getCurationPoolTokens). Signal magnitude only scales rewards; it does not gate any
        // code path. Other config (unpause, maxPOIStaleness, thawing period) is done by
        // FullStackHarness._configureProtocol.
        vm.startPrank(governor);
        IRealRewardsManager(address(realRewardsManager)).setSubgraphService(address(subgraphService));
        IRealRewardsManager(address(realRewardsManager)).setIssuancePerBlock(RM_ISSUANCE_PER_BLOCK);
        vm.stopPrank();

        token.mint(address(curation), RM_CURATION_SIGNAL);
        vm.mockCall(
            address(curation),
            abi.encodeWithSignature("getCurationPoolTokens(bytes32)"),
            abi.encode(RM_CURATION_SIGNAL)
        );
    }
}
