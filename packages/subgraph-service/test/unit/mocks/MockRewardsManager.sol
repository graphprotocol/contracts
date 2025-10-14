// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";

import { MockGRTToken } from "./MockGRTToken.sol";

interface IRewardsIssuer {
    function getAllocationData(
        address allocationId
    )
        external
        view
        returns (
            bool isActive,
            address indexer,
            bytes32 subgraphDeploymentId,
            uint256 tokens,
            uint256 accRewardsPerAllocatedToken
        );
}

contract MockRewardsManager is IRewardsManager {
    using PPMMath for uint256;

    MockGRTToken public token;
    uint256 public rewardsPerSignal;
    uint256 public rewardsPerSubgraphAllocationUpdate;
    mapping(bytes32 => bool) public subgraphs;

    uint256 private constant FIXED_POINT_SCALING_FACTOR = 1e18;

    constructor(MockGRTToken _token, uint256 _rewardsPerSignal, uint256 _rewardsPerSubgraphAllocationUpdate) {
        token = _token;
        rewardsPerSignal = _rewardsPerSignal;
        rewardsPerSubgraphAllocationUpdate = _rewardsPerSubgraphAllocationUpdate;
    }

    // -- Config --

    function setIssuancePerBlock(uint256) external {}

    function setMinimumSubgraphSignal(uint256) external {}

    function setSubgraphService(address) external {}

    // -- Denylist --

    function setSubgraphAvailabilityOracle(address) external {}

    function setDenied(bytes32, bool) external {}

    function setDeniedMany(bytes32[] calldata, bool[] calldata) external {}

    function isDenied(bytes32) external view returns (bool) {}

    // -- Getters --

    function getNewRewardsPerSignal() external view returns (uint256) {}

    function getAccRewardsPerSignal() external view returns (uint256) {}

    function getAccRewardsForSubgraph(bytes32) external view returns (uint256) {}

    function getAccRewardsPerAllocatedToken(bytes32) external view returns (uint256, uint256) {}

    function getRewards(address, address) external view returns (uint256) {}

    function calcRewards(uint256, uint256) external pure returns (uint256) {}

    function getRewardsIssuancePerBlock() external view returns (uint256) {}

    // -- Setters --

    function setRewardsEligibilityOracle(address newRewardsEligibilityOracle) external {}

    // -- Updates --

    function updateAccRewardsPerSignal() external returns (uint256) {}

    function takeRewards(address _allocationID) external returns (uint256) {
        address rewardsIssuer = msg.sender;
        (bool isActive, , , uint256 tokens, uint256 accRewardsPerAllocatedToken) = IRewardsIssuer(rewardsIssuer)
            .getAllocationData(_allocationID);

        if (!isActive) {
            return 0;
        }

        uint256 accRewardsPerTokens = tokens.mulPPM(rewardsPerSignal);
        uint256 rewards = accRewardsPerTokens - accRewardsPerAllocatedToken;
        token.mint(rewardsIssuer, rewards);
        return rewards;
    }

    // -- Hooks --

    function onSubgraphSignalUpdate(bytes32) external pure returns (uint256) {}

    function onSubgraphAllocationUpdate(bytes32 _subgraphDeploymentID) external returns (uint256) {
        if (subgraphs[_subgraphDeploymentID]) {
            return rewardsPerSubgraphAllocationUpdate;
        }

        subgraphs[_subgraphDeploymentID] = true;
        return 0;
    }

    function subgraphService() external pure returns (address) {
        return address(0x00);
    }
}
