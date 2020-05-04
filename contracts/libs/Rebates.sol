pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";


/*
 * @title A collection of data structures and functions to manage Rebates
 *        Used for low-level state changes, require() conditions should be evaluated
 *        at the caller function scope.
 */

library Rebates {
    using SafeMath for uint256;

    // Tracks per indexNode/subgraphID settlement
    struct Settlement {
        uint256 fees;
        uint256 allocation;
    }

    // Tracks per epoch settlements
    struct Pool {
        uint256 fees;
        uint256 allocation;
        uint256 settlementsCount;
        // Settlements in this pool : indexNode => subgraphID => Settlement
        mapping(address => mapping(bytes32 => Settlement)) settlements;
    }

    /**
     * @dev Deposit tokens into the rebate pool
     * @param _indexNode Address of the index node settling a channel
     * @param _subgraphID ID of the settled subgraph
     * @param _tokens Amount of fees collected in tokens
     * @param _allocation Effective stake allocated by the index node for a period of epochs
     * @return A settlement struct created after adding to rebate pool
     */
    function add(
        Rebates.Pool storage pool,
        address _indexNode,
        bytes32 _subgraphID,
        uint256 _tokens,
        uint256 _allocation
    ) internal returns (Rebates.Settlement storage) {
        pool.fees = pool.fees.add(_tokens);
        pool.allocation = pool.allocation.add(_allocation);
        pool.settlements[_indexNode][_subgraphID] = Settlement(_tokens, _allocation);
        pool.settlementsCount += 1;

        return pool.settlements[_indexNode][_subgraphID];
    }

    /**
     * @dev Redeem tokens from the rebate pool
     * @param _indexNode Address of the index node claiming a rebate
     * @param _subgraphID ID of the claimed subgraph rebate
     * @return Amount of tokens to be released according to Cobb-Douglas rebate reward formula
     */
    function redeem(Rebates.Pool storage pool, address _indexNode, bytes32 _subgraphID)
        internal
        returns (uint256)
    {
        Rebates.Settlement storage settlement = pool.settlements[_indexNode][_subgraphID];

        // Production function reward calculation
        // TODO: exponential calculation when alpha < 1...
        uint256 alpha = 1;
        uint256 termA = settlement.allocation.div(pool.allocation)**(alpha);
        uint256 termB = settlement.fees.div(pool.fees)**(1 - alpha);
        uint256 tokens = termA.mul(termB);

        // Redeem settlement
        delete pool.settlements[_indexNode][_subgraphID];
        pool.settlementsCount -= 1;

        return tokens;
    }
}
