// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "./Cobbs.sol";
import "./Exponential.sol";

/**
 * @title A collection of data structures and functions to manage Rebates
 *        Used for low-level state changes, require() conditions should be evaluated
 *        at the caller function scope.
 *
 *        Supports two types of rebate pools:
 *          - Cobb-Douglas, the initial rebates implementation (deprecated)
 *          - Exponential, the new rebates implementation
 *
 *        Note that Cobb-Douglas rebates logic can't be removed to allow open pools to be closed.
 */
library Rebates {
    using SafeMath for uint256;
    using Rebates for Rebates.Pool;

    // Tracks stats for allocations closed on a particular epoch for claiming
    // The pool also keeps tracks of total query fees collected and stake used
    // Only one rebate pool exists per epoch
    struct Pool {
        uint256 fees; // total query fees in the rebate pool
        uint256 effectiveAllocatedStake; // total effective allocation of stake
        uint256 claimedRewards; // total claimed rewards from the rebate pool
        uint32 unclaimedAllocationsCount; // amount of unclaimed allocations
        uint32 alphaNumerator; // numerator of `alpha` in the rebates function (both types)
        uint32 alphaDenominator; // denominator of `alpha` in the rebates function (both types)
        uint32 lambdaNumerator; // numerator of `lambda` in the exponential rebates function
        uint32 lambdaDenominator; // denominator of `lambda` in the exponential rebates function
    }

    /**
     * @dev Init the rebate pool with the rebate parameters.
     * @param _alphaNumerator Numerator of `alpha` in the rebates function
     * @param _alphaDenominator Denominator of `alpha` in the rebates function
     * @param _lambdaNumerator Numerator of `lambda` in the exponential rebates function
     * @param _lambdaDenominator Denominator of `lambda` in the exponential rebates function
     */
    function init(
        Rebates.Pool storage pool,
        uint32 _alphaNumerator,
        uint32 _alphaDenominator,
        uint32 _lambdaNumerator,
        uint32 _lambdaDenominator
    ) internal {
        pool.alphaNumerator = _alphaNumerator;
        pool.alphaDenominator = _alphaDenominator;
        pool.lambdaNumerator = _lambdaNumerator;
        pool.lambdaDenominator = _lambdaDenominator;
    }

    /**
     * @dev Return true if the rebate pool was already initialized.
     */
    function exists(Rebates.Pool storage pool) internal view returns (bool) {
        return pool.effectiveAllocatedStake > 0;
    }

    /**
     * @dev Return the amount of unclaimed fees.
     */
    function unclaimedFees(Rebates.Pool storage pool) internal view returns (uint256) {
        return pool.fees.sub(pool.claimedRewards);
    }

    /**
     * @dev Deposit tokens into the rebate pool.
     * @param _indexerFees Amount of fees collected in tokens
     * @param _indexerEffectiveAllocatedStake Effective stake allocated by indexer for a period of epochs
     */
    function addToPool(
        Rebates.Pool storage pool,
        uint256 _indexerFees,
        uint256 _indexerEffectiveAllocatedStake
    ) internal {
        pool.fees = pool.fees.add(_indexerFees);
        pool.effectiveAllocatedStake = pool.effectiveAllocatedStake.add(
            _indexerEffectiveAllocatedStake
        );
        pool.unclaimedAllocationsCount += 1;
    }

    /**
     * @dev Redeem tokens from the rebate pool.
     * @param _indexerFees Amount of fees collected in tokens
     * @param _indexerEffectiveAllocatedStake Effective stake allocated by indexer for a period of epochs
     * @return Amount of reward tokens according rebate formula
     */
    function redeem(
        Rebates.Pool storage pool,
        uint256 _indexerFees,
        uint256 _indexerEffectiveAllocatedStake
    ) internal returns (uint256) {
        uint256 rebateReward = 0;

        // Calculate the rebate rewards for the indexer
        if (pool.fees > 0 && pool.effectiveAllocatedStake > 0) {
            if (pool.lambdaDenominator > 0) {
                // Exponential rebates
                rebateReward = LibExponential.exponentialRebates(
                    _indexerFees,
                    _indexerEffectiveAllocatedStake,
                    pool.alphaNumerator,
                    pool.alphaDenominator,
                    pool.lambdaNumerator,
                    pool.lambdaDenominator
                );
            } else {
                // (Deprecated) Cobb-Douglas rebates
                // Keeping this logic to allow existing open pools to be closed
                rebateReward = LibCobbDouglas.cobbDouglas(
                    pool.fees, // totalRewards
                    _indexerFees,
                    pool.fees,
                    _indexerEffectiveAllocatedStake,
                    pool.effectiveAllocatedStake,
                    pool.alphaNumerator,
                    pool.alphaDenominator
                );
            }

            // Under NO circumstance we will reward more than total fees in the pool
            uint256 _unclaimedFees = pool.unclaimedFees();
            if (rebateReward > _unclaimedFees) {
                rebateReward = _unclaimedFees;
            }
        }

        // Update pool state
        pool.unclaimedAllocationsCount -= 1;
        pool.claimedRewards = pool.claimedRewards.add(rebateReward);

        return rebateReward;
    }
}
