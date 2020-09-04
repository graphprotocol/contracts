pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "./abdk-libraries-solidity/ABDKMathQuad.sol";

/**
 * @title A collection of data structures and functions to manage Rebates
 *        Used for low-level state changes, require() conditions should be evaluated
 *        at the caller function scope.
 */
library Rebates {
    using SafeMath for uint256;
    using ABDKMathQuad for uint256;
    using ABDKMathQuad for bytes16;

    // Tracks allocations closed on an epoch for claiming
    // The pool also keeps tracks of total query fees collected and stake used
    // It is intended to have one pool per epoch
    struct Pool {
        uint256 fees; // total fees in the rebate pool
        uint256 allocation; // total effective allocation accumulated
        uint256 unclaimedAllocationsCount; // amount of unclaimed allocations
    }

    /**
     * @dev Deposit tokens into the rebate pool
     * @param _tokens Amount of fees collected in tokens
     * @param _allocation Effective stake allocated by the indexer for a period of epochs
     */
    function addToPool(
        Rebates.Pool storage pool,
        uint256 _tokens,
        uint256 _allocation
    ) internal {
        pool.fees = pool.fees.add(_tokens);
        pool.allocation = pool.allocation.add(_allocation);
        pool.unclaimedAllocationsCount += 1;
    }

    /**
     * @dev Redeem tokens from the rebate pool
     * @param _tokens Amount of fees collected in tokens
     * @param _allocation Effective stake allocated by the indexer for a period of epochs
     * @return Amount of tokens to be released according to Cobb-Douglas rebate reward formula
     */
    function redeem(
        Rebates.Pool storage pool,
        uint256 _tokens,
        uint256 _allocation
    ) internal returns (uint256) {
        uint256 tokens = calcRebateReward(
            2, // TODO: Fixed to do the sqrt()
            _tokens,
            _allocation,
            pool.allocation,
            pool.fees
        );
        pool.unclaimedAllocationsCount -= 1;
        return tokens;
    }

    /**
     * @dev Calculate rebate using production function
     * @param _indexerAlloc Effective allocation for (epoch,indexer,subgraphDeploymentID)
     * @param _indexerFees Fees collected on (epoch,indexer,subgraphDeploymentID)
     * @param _poolAlloc Pooled effective allocation for epoch
     * @param _poolFees Pooled collected fees for epoch
     * @return Amount of tokens to be released according to Cobb-Douglas rebate reward formula
     */
    function calcRebateReward(
        uint256, /*_invAlpha*/
        uint256 _indexerAlloc,
        uint256 _indexerFees,
        uint256 _poolAlloc,
        uint256 _poolFees
    ) public pure returns (uint256) {
        // NOTE: We sqrt() because alpha is fractional so we expect the inverse of alpha
        if (_poolAlloc == 0 || _poolFees == 0) {
            return 0;
        }

        // Here we use ABDKMathQuad to do the square root of terms
        // We have to covert it to a bytes16 fixed point number, do sqrt(), then convert it
        // back to uint256. uint256 wraps the result of toUInt(), since it returns uint64
        bytes16 iAlloc = _indexerAlloc.fromUInt();
        bytes16 pAlloc = _poolAlloc.fromUInt();
        bytes16 aRatio = iAlloc.div(pAlloc);

        bytes16 iFees = _indexerFees.fromUInt();
        bytes16 pFees = _poolFees.fromUInt();
        bytes16 fRatio = iFees.div(pFees);

        bytes16 termA = aRatio.sqrt();
        bytes16 termB = fRatio.sqrt();

        bytes16 reward = termA.mul(termB);

        return uint256(pFees.mul(reward).toUInt());
    }
}
