// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Vm.sol";
import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";

import { ProtocolFixture } from "../shared/ProtocolFixture.t.sol";
import { MockGraphToken } from "../mocks/MockGraphToken.sol";
import { IRewardsManagerLike } from "./IRewardsManagerLike.sol";
import { RMCurationMock } from "./mocks/RMCurationMock.sol";
import { RMEligibilityOracleMock } from "./mocks/RMEligibilityOracleMock.sol";
import { RMIssuanceAllocatorMock } from "./mocks/RMIssuanceAllocatorMock.sol";
import { RMIssuerMock } from "./mocks/RMIssuerMock.sol";

/// @notice Shared setup for RewardsManager tests: the 0.7.6 RewardsManager artifact behind a GraphProxy,
/// wired to 0.8 mocks for GraphToken, Curation and the rewards issuer (subgraph service).
contract RewardsManagerSharedTest is ProtocolFixture {
    uint256 internal constant ISSUANCE_PER_BLOCK = 200 ether;
    uint256 internal constant SIGNAL = 1500 ether;
    uint256 internal constant ALLOCATION = 12_500 ether;
    /// Blocks per `helpers.mineEpoch`: the old tests set the epoch length to 10
    uint256 internal constant EPOCH_LENGTH = 10;

    IRewardsManagerLike internal rm;
    MockGraphToken internal token;
    RMCurationMock internal curation;
    RMIssuerMock internal issuer;
    RMIssuanceAllocatorMock internal allocator;
    RMEligibilityOracleMock internal oracle;

    address internal indexer = makeAddr("indexer");

    function setUp() public virtual {
        vm.warp(1_700_000_000);
        vm.roll(1_000_000);
        _deployProtocolBase();

        address impl = _deployArtifact(
            string.concat(PKG_ARTIFACTS, "rewards/RewardsManager.sol/RewardsManager.json"),
            ""
        );
        rm = IRewardsManagerLike(
            _deployBehindProxy(impl, abi.encodeCall(IRewardsManagerLike.initialize, (address(controller))))
        );

        token = new MockGraphToken();
        curation = new RMCurationMock(token);
        issuer = new RMIssuerMock();
        allocator = new RMIssuanceAllocatorMock();
        oracle = new RMEligibilityOracleMock(true);

        _registerContract("GraphToken", address(token));
        _registerContract("Curation", address(curation));
        rm.syncAllContracts();

        curation.setRewardsManager(address(rm));
        issuer.setRewardsManager(address(rm));

        vm.startPrank(governor);
        rm.setSubgraphService(address(issuer));
        rm.setIssuancePerBlock(ISSUANCE_PER_BLOCK);
        vm.stopPrank();

        vm.label(address(rm), "RewardsManager");
        vm.label(address(token), "GraphToken");
        vm.label(address(curation), "Curation");
        vm.label(address(issuer), "RewardsIssuer");
        vm.label(address(allocator), "IssuanceAllocator");
        vm.label(address(oracle), "EligibilityOracle");
    }

    // -- Helpers --

    function _signal(bytes32 sd, uint256 tokens) internal {
        curation.signal(sd, tokens);
    }

    function _allocate(address allocationId, bytes32 sd, uint256 tokens) internal {
        issuer.allocate(allocationId, indexer, sd, tokens);
    }

    function _close(address allocationId) internal returns (uint256) {
        return issuer.close(allocationId);
    }

    /// Signal `SIGNAL`, then allocate `ALLOCATION` one block later, as the old `setupIndexerAllocation` did
    /// in separate transactions: the pre-allocation block is reclaimed under the subgraph's condition.
    function _signalThenAllocate(bytes32 sd, address allocationId) internal {
        _signal(sd, SIGNAL);
        vm.roll(block.number + 1);
        _allocate(allocationId, sd, ALLOCATION);
    }

    /// Sets the fixture's `oracle` as the eligibility oracle, answering `eligibleByDefault` for every indexer.
    function _useEligibilityOracle(bool eligibleByDefault) internal {
        oracle.setDefaultResponse(eligibleByDefault);
        vm.prank(governor);
        rm.setProviderEligibilityOracle(IProviderEligibility(address(oracle)));
    }

    function _expectedRewardsPerSignal(uint256 blocks, uint256 totalSignal) internal pure returns (uint256) {
        return (blocks * ISSUANCE_PER_BLOCK * 1e18) / totalSignal;
    }

    /// Rewards a subgraph with `subgraphSignal` accrues over `blocks` while total signal is `totalSignal`.
    function _expectedSubgraphRewards(
        uint256 blocks,
        uint256 totalSignal,
        uint256 subgraphSignal
    ) internal pure returns (uint256) {
        return (_expectedRewardsPerSignal(blocks, totalSignal) * subgraphSignal) / 1e18;
    }

    function _expectedRewardsPerAllocatedToken(
        uint256 subgraphRewards,
        uint256 allocatedTokens
    ) internal pure returns (uint256) {
        return (subgraphRewards * 1e18) / allocatedTokens;
    }

    /// Rewards for an allocation of `tokens` out of `allocatedTokens` on a subgraph holding all the signal.
    function _expectedAllocationRewards(
        uint256 blocks,
        uint256 tokens,
        uint256 allocatedTokens
    ) internal pure returns (uint256) {
        uint256 subgraphRewards = _expectedSubgraphRewards(blocks, SIGNAL, SIGNAL);
        return (_expectedRewardsPerAllocatedToken(subgraphRewards, allocatedTokens) * tokens) / 1e18;
    }

    function _assertNotEmitted(Vm.Log[] memory logs, bytes32 topic) internal view {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == address(rm)) assertTrue(logs[i].topics[0] != topic, "unexpected event");
        }
    }
}
