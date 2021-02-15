// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "./MathUtils.sol";

/**
 * @title A collection of data structures and functions to manage the Indexer Stake state.
 *        Used for low-level state changes, require() conditions should be evaluated
 *        at the caller function scope.
 */
library Stakes {
    using SafeMath for uint256;
    using Stakes for Stakes.Indexer;

    struct Indexer {
        uint256 tokensStaked; // Tokens on the indexer stake (staked by the indexer)
        uint256 tokensAllocated; // Tokens used in allocations
        uint256 tokensLocked; // Tokens locked for withdrawal subject to thawing period
        uint256 tokensLockedUntil; // Block when locked tokens can be withdrawn
    }

    /**
     * @dev Deposit tokens to the indexer stake.
     * @param _self Stake data
     * @param _tokens Amount of tokens to deposit
     */
    function deposit(Stakes.Indexer storage _self, uint256 _tokens) internal {
        _self.tokensStaked = _self.tokensStaked.add(_tokens);
    }

    /**
     * @dev Release tokens from the indexer stake.
     * @param _self Stake data
     * @param _tokens Amount of tokens to release
     */
    function release(Stakes.Indexer storage _self, uint256 _tokens) internal {
        _self.tokensStaked = _self.tokensStaked.sub(_tokens);
    }

    /**
     * @dev Allocate tokens from the main stack to a SubgraphDeployment.
     * @param _self Stake data
     * @param _tokens Amount of tokens to allocate
     */
    function allocate(Stakes.Indexer storage _self, uint256 _tokens) internal {
        _self.tokensAllocated = _self.tokensAllocated.add(_tokens);
    }

    /**
     * @dev Unallocate tokens from a SubgraphDeployment back to the main stack.
     * @param _self Stake data
     * @param _tokens Amount of tokens to unallocate
     */
    function unallocate(Stakes.Indexer storage _self, uint256 _tokens) internal {
        _self.tokensAllocated = _self.tokensAllocated.sub(_tokens);
    }

    /**
     * @dev Lock tokens until a thawing period pass.
     * @param _self Stake data
     * @param _tokens Amount of tokens to unstake
     * @param _period Period in blocks that need to pass before withdrawal
     */
    function lockTokens(
        Stakes.Indexer storage _self,
        uint256 _tokens,
        uint256 _period
    ) internal {
        // Take into account period averaging for multiple unstake requests
        uint256 lockingPeriod = _period;
        if (_self.tokensLocked > 0) {
            lockingPeriod = MathUtils.weightedAverage(
                MathUtils.diff(_self.tokensLockedUntil, block.number),
                _self.tokensLocked,
                _period,
                _tokens
            );
        }

        // Update balances
        _self.tokensLocked = _self.tokensLocked.add(_tokens);
        _self.tokensLockedUntil = block.number.add(lockingPeriod);
    }

    /**
     * @dev Unlock tokens.
     * @param _self Stake data
     * @param _tokens Amount of tokens to unkock
     */
    function unlockTokens(Stakes.Indexer storage _self, uint256 _tokens) internal {
        _self.tokensLocked = _self.tokensLocked.sub(_tokens);
        if (_self.tokensLocked == 0) {
            _self.tokensLockedUntil = 0;
        }
    }

    /**
     * @dev Take all tokens out from the locked stake for withdrawal.
     * @param _self Stake data
     * @return Amount of tokens being withdrawn
     */
    function withdrawTokens(Stakes.Indexer storage _self) internal returns (uint256) {
        // Calculate tokens that can be released
        uint256 tokensToWithdraw = _self.tokensWithdrawable();

        if (tokensToWithdraw > 0) {
            // Reset locked tokens
            _self.unlockTokens(tokensToWithdraw);

            // Decrease indexer stake
            _self.release(tokensToWithdraw);
        }

        return tokensToWithdraw;
    }

    /**
     * @dev Return the amount of tokens used in allocations and locked for withdrawal.
     * @param _self Stake data
     * @return Token amount
     */
    function tokensUsed(Stakes.Indexer memory _self) internal pure returns (uint256) {
        return _self.tokensAllocated.add(_self.tokensLocked);
    }

    /**
     * @dev Return the amount of tokens staked not considering the ones that are already going
     * through the thawing period or are ready for withdrawal. We call it secure stake because
     * it is not subject to change by a withdraw call from the indexer.
     * @param _self Stake data
     * @return Token amount
     */
    function tokensSecureStake(Stakes.Indexer memory _self) internal pure returns (uint256) {
        return _self.tokensStaked.sub(_self.tokensLocked);
    }

    /**
     * @dev Tokens free balance on the indexer stake that can be used for any purpose.
     * Any token that is allocated cannot be used as well as tokens that are going through the
     * thawing period or are withdrawable
     * Calc: tokensStaked - tokensAllocated - tokensLocked
     * @param _self Stake data
     * @return Token amount
     */
    function tokensAvailable(Stakes.Indexer memory _self) internal pure returns (uint256) {
        return _self.tokensAvailableWithDelegation(0);
    }

    /**
     * @dev Tokens free balance on the indexer stake that can be used for allocations.
     * This function accepts a parameter for extra delegated capacity that takes into
     * account delegated tokens
     * @param _self Stake data
     * @param _delegatedCapacity Amount of tokens used from delegators to calculate availability
     * @return Token amount
     */
    function tokensAvailableWithDelegation(Stakes.Indexer memory _self, uint256 _delegatedCapacity)
        internal
        pure
        returns (uint256)
    {
        uint256 tokensCapacity = _self.tokensStaked.add(_delegatedCapacity);
        uint256 _tokensUsed = _self.tokensUsed();
        // If more tokens are used than the current capacity, the indexer is overallocated.
        // This means the indexer doesn't have available capacity to create new allocations.
        // We can reach this state when the indexer has funds allocated and then any
        // of these conditions happen:
        // - The delegationCapacity ratio is reduced.
        // - The indexer stake is slashed.
        // - A delegator removes enough stake.
        if (_tokensUsed > tokensCapacity) {
            // Indexer stake is over allocated: return 0 to avoid stake to be used until
            // the overallocation is restored by staking more tokens, unallocating tokens
            // or using more delegated funds
            return 0;
        }
        return tokensCapacity.sub(_tokensUsed);
    }

    /**
     * @dev Tokens available for withdrawal after thawing period.
     * @param _self Stake data
     * @return Token amount
     */
    function tokensWithdrawable(Stakes.Indexer memory _self) internal view returns (uint256) {
        // No tokens to withdraw before locking period
        if (_self.tokensLockedUntil == 0 || block.number < _self.tokensLockedUntil) {
            return 0;
        }
        return _self.tokensLocked;
    }
}
