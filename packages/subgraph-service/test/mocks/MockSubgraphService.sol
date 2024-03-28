// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./MockGRTToken.sol";
import "../../contracts/ISubgraphService.sol";

contract MockSubgraphService is ISubgraphService {
    MockGRTToken public grtToken;

    mapping (address allocationID => Allocation) public allocations;

    constructor(address _grtTokenAddress) {
        grtToken = MockGRTToken(_grtTokenAddress);
    }

    function slash(address serviceProvider, uint256 tokens, uint256 rewards) external {
        grtToken.mint(msg.sender, rewards);
        grtToken.burnFrom(serviceProvider, tokens);
    }

    function register(address provisionId, string calldata url, string calldata geohash, uint256 delegatorQueryFeeCut)
        external
        override
    {
        // Get provision from Staking contract
        // Validate provision parameters meet DS requirements
    }

    function _register(address provisionId, string calldata url, string calldata geohash, uint256 delegatorQueryFeeCut)
        internal
    {}

    function allocate(address serviceProvider, bytes32 subgraphDeploymentID, uint256 tokens, address allocationID) external {
        Allocation memory allocation = ISubgraphService.Allocation({
            serviceProvider: serviceProvider,
            subgraphDeploymentID: subgraphDeploymentID,
            tokens: tokens,
            createdAtEpoch: block.timestamp,
            closedAtEpoch: 0,
            collectedFees: 0,
            __DEPRECATED_effectiveAllocation: 0,
            accRewardsPerAllocatedToken: 0,
            distributedRebates: 0
        });
        allocations[allocationID] = allocation;
    }

    function getAllocation(address allocationID) external view returns (Allocation memory) {
        return allocations[allocationID];
    }
}
