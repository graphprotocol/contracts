// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../upgrades/GraphUpgradeable.sol";

import "./ReservoirStorage.sol";
import "./IReservoir.sol";

/**
 * @title Rewards Reservoir base contract
 * @dev This contract acts as a reservoir/vault for the rewards to be distributed on Layer 1 or Layer 2.
 * It provides functions to compute accumulated and new total rewards at a particular block number.
 * This base contract provides functionality that is common to L1 and L2, to be extended on each layer.
 */
abstract contract Reservoir is GraphUpgradeable, ReservoirV1Storage, IReservoir {
    using SafeMath for uint256;

    uint256 private constant MAX_UINT256 = 2**256 - 1;
    uint256 internal constant TOKEN_DECIMALS = 1e18;
    uint256 internal constant MIN_ISSUANCE_RATE = 1e18;

    /**
     * @dev Approve the RewardsManager to manage the reservoir's token funds
     */
    function approveRewardsManager() external override onlyGovernor {
        graphToken().approve(address(rewardsManager()), MAX_UINT256);
    }

    /**
     * @dev Get accumulated total rewards on this layer at a particular block
     * @param blocknum Block number at which to calculate rewards
     * @return totalRewards Accumulated total rewards on this layer
     */
    function getAccumulatedRewards(uint256 blocknum)
        public
        view
        override
        returns (uint256 totalRewards)
    {
        // R(t) = R(t0) + (DeltaR(t, t0))
        totalRewards = accumulatedLayerRewards + getNewRewards(blocknum);
    }

    /**
     * @dev Get new total rewards on this layer at a particular block, since the last drip event.
     * Must be implemented by the reservoir on each layer.
     * @param blocknum Block number at which to calculate rewards
     * @return deltaRewards New total rewards on this layer since the last drip
     */
    function getNewRewards(uint256 blocknum)
        public
        view
        virtual
        override
        returns (uint256 deltaRewards);

    /**
     * @dev Raises x to the power of n with scaling factor of base.
     * Based on: https://github.com/makerdao/dss/blob/master/src/pot.sol#L81
     * @param x Base of the exponentiation
     * @param n Exponent
     * @param base Scaling factor
     * @return z Exponential of n with base x
     */
    function _pow(
        uint256 x,
        uint256 n,
        uint256 base
    ) internal pure returns (uint256 z) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            switch x
            case 0 {
                switch n
                case 0 {
                    z := base
                }
                default {
                    z := 0
                }
            }
            default {
                switch mod(n, 2)
                case 0 {
                    z := base
                }
                default {
                    z := x
                }
                let half := div(base, 2) // for rounding.
                for {
                    n := div(n, 2)
                } n {
                    n := div(n, 2)
                } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) {
                        revert(0, 0)
                    }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) {
                        revert(0, 0)
                    }
                    x := div(xxRound, base)
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) {
                            revert(0, 0)
                        }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) {
                            revert(0, 0)
                        }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }
}
