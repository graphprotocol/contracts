// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "./MathUtils.sol";

library Rewards {
    using SafeMath for uint256;

    struct Pool {
        uint256 tokensLocked;
        uint256 tokensLockedUntil; // Block when locked tokens can be withdrawn
    }

    /**
     * @dev Reset the rewards pool.
     * @param _self Rewards pool
     */
    function reset(Rewards.Pool storage _self) internal {
        _self.tokensLocked = 0;
        _self.tokensLockedUntil = 0;
    }

    /**
     * @dev Lock tokens until a thawing period pass.
     * @param _self Rewards pool
     * @param _tokens Amount of tokens to unstake
     * @param _period Period in blocks that need to pass before withdrawal
     */
    function lockTokens(
        Rewards.Pool storage _self,
        uint256 _tokens,
        uint256 _period
    ) internal {
        // Take into account period averaging for multiple deposits
        uint256 lockingPeriod = _period;
        if (_self.tokensLockedUntil > 0) {
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
}
