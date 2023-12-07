// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.6.12 <0.8.0;

/**
 * @title Staking Data interface
 * @dev This interface defines some structures used by the Staking contract.
 */
interface IStakingData {
    /**
     * @dev Allocate GRT tokens for the purpose of serving queries of a subgraph deployment
     * An allocation is created in the allocate() function and closed in closeAllocation()
     */
    struct Allocation {
        address indexer;
        bytes32 subgraphDeploymentID;
        uint256 tokens; // Tokens allocated to a SubgraphDeployment
        uint256 createdAtEpoch; // Epoch when it was created
        uint256 closedAtEpoch; // Epoch when it was closed
        uint256 collectedFees; // Collected fees for the allocation
        uint256 __DEPRECATED_effectiveAllocation; // solhint-disable-line var-name-mixedcase
        uint256 accRewardsPerAllocatedToken; // Snapshot used for reward calc
        uint256 distributedRebates; // Collected rebates that have been rebated
    }

    // -- Delegation Data --

    /**
     * @dev Delegation pool information. One per indexer.
     */
    struct DelegationPool {
        uint32 __DEPRECATED_cooldownBlocks; // solhint-disable-line var-name-mixedcase
        uint32 indexingRewardCut; // in PPM
        uint32 queryFeeCut; // in PPM
        uint256 updatedAtBlock; // Block when the pool was last updated
        uint256 tokens; // Total tokens as pool reserves
        uint256 shares; // Total shares minted in the pool
        mapping(address => Delegation) delegators; // Mapping of delegator => Delegation
    }

    /**
     * @dev Individual delegation data of a delegator in a pool.
     */
    struct Delegation {
        uint256 shares; // Shares owned by a delegator in the pool
        uint256 tokensLocked; // Tokens locked for undelegation
        uint256 tokensLockedUntil; // Epoch when locked tokens can be withdrawn
    }

    /**
     * @dev Rebates parameters. Used to avoid stack too deep errors in Staking initialize function.
     */
    struct RebatesParameters {
        uint32 alphaNumerator;
        uint32 alphaDenominator;
        uint32 lambdaNumerator;
        uint32 lambdaDenominator;
    }
}
