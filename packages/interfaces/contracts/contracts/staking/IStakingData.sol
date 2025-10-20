// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title Staking Data interface
 * @author Edge & Node
 * @notice This interface defines some structures used by the Staking contract.
 */
interface IStakingData {
    /**
     * @dev Allocate GRT tokens for the purpose of serving queries of a subgraph deployment
     * An allocation is created in the allocate() function and closed in closeAllocation()
     * @param indexer Address of the indexer that owns the allocation
     * @param subgraphDeploymentID Subgraph deployment ID being allocated to
     * @param tokens Tokens allocated to a SubgraphDeployment
     * @param createdAtEpoch Epoch when it was created
     * @param closedAtEpoch Epoch when it was closed
     * @param collectedFees Collected fees for the allocation
     * @param __DEPRECATED_effectiveAllocation Deprecated field for effective allocation
     * @param accRewardsPerAllocatedToken Snapshot used for reward calc
     * @param distributedRebates Collected rebates that have been rebated
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
     * @param __DEPRECATED_cooldownBlocks Deprecated field for cooldown blocks
     * @param indexingRewardCut Indexing reward cut in PPM
     * @param queryFeeCut Query fee cut in PPM
     * @param updatedAtBlock Block when the pool was last updated
     * @param tokens Total tokens as pool reserves
     * @param shares Total shares minted in the pool
     * @param delegators Mapping of delegator => Delegation
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
     * @param shares Shares owned by a delegator in the pool
     * @param tokensLocked Tokens locked for undelegation
     * @param tokensLockedUntil Epoch when locked tokens can be withdrawn
     */
    struct Delegation {
        uint256 shares; // Shares owned by a delegator in the pool
        uint256 tokensLocked; // Tokens locked for undelegation
        uint256 tokensLockedUntil; // Epoch when locked tokens can be withdrawn
    }

    /**
     * @dev Rebates parameters. Used to avoid stack too deep errors in Staking initialize function.
     * @param alphaNumerator Alpha parameter numerator for rebate calculation
     * @param alphaDenominator Alpha parameter denominator for rebate calculation
     * @param lambdaNumerator Lambda parameter numerator for rebate calculation
     * @param lambdaDenominator Lambda parameter denominator for rebate calculation
     */
    struct RebatesParameters {
        uint32 alphaNumerator;
        uint32 alphaDenominator;
        uint32 lambdaNumerator;
        uint32 lambdaDenominator;
    }
}
