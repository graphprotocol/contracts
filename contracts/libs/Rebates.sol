pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../abdk-libraries-solidity/ABDKMath64x64.sol";

/**
 * @title A collection of data structures and functions to manage Rebates
 *        Used for low-level state changes, require() conditions should be evaluated
 *        at the caller function scope.
 */
library Rebates {
    using SafeMath for uint256;
    using ABDKMath64x64 for uint256;
    using ABDKMath64x64 for int128;

    // Tracks allocation settlements in a Pool per epoch
    struct Pool {
        uint256 fees;
        uint256 allocation;
        uint256 settlementsCount;
    }

    /**
     * @dev Deposit tokens into the rebate pool
     * @param _tokens Amount of fees collected in tokens
     * @param _allocation Effective stake allocated by the indexer for a period of epochs
     * @return A settlement struct created after adding to rebate pool
     */
    function add(
        Rebates.Pool storage pool,
        uint256 _tokens,
        uint256 _allocation
    ) internal {
        pool.fees = pool.fees.add(_tokens);
        pool.allocation = pool.allocation.add(_allocation);
        pool.settlementsCount += 1;
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
        pool.settlementsCount -= 1;
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

        // Here we use ABDKMath64x64 to do the square root of terms
        // We have to covert it to a 64.64 fixed point number, do sqrt(), then convert it
        // back to uint256. uint256 wraps the result of toUInt(), since it returns uint64
        uint256 allocRatio = _indexerAlloc.div(_poolAlloc);
        uint256 feesRatio = _indexerFees.div(_poolFees);
        uint256 termA = uint256(allocRatio.fromUInt().sqrt().toUInt());
        uint256 termB = uint256(feesRatio.fromUInt().sqrt().toUInt());
        return _poolFees.mul(termA.mul(termB));
    }
}
