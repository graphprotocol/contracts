// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

interface ISubgraphService {
    struct Allocation {
        address serviceProvider;
        bytes32 subgraphDeploymentID;
        uint256 tokens; // Tokens allocated to a SubgraphDeployment
        uint256 createdAtEpoch; // Epoch when it was created
        uint256 closedAtEpoch; // Epoch when it was closed
        uint256 collectedFees; // Collected fees for the allocation
        uint256 __DEPRECATED_effectiveAllocation; // solhint-disable-line var-name-mixedcase
        uint256 accRewardsPerAllocatedToken; // Snapshot used for reward calc
        uint256 distributedRebates; // Collected rebates that have been rebated
    }

    // register as a provider in the data service
    function register(address provisionId, string calldata url, string calldata geohash, uint256 delegatorQueryFeeCut)
        external;

    // register as a provider in the data service, create the required provision first
    // function provisionAndRegister(
    //     uint256 tokens,
    //     string calldata url,
    //     string calldata geohash,
    //     uint256 delegatorQueryFeeCut
    // ) external;

    function getAllocation(address allocationID) external view returns (Allocation memory);
    function slash(address serviceProvider, uint256 tokens, uint256 rewards) external;
}
