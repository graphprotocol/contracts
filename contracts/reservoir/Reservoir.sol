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
    uint256 internal constant FIXED_POINT_SCALING_FACTOR = 1e18;
    uint256 internal constant MIN_ISSUANCE_RATE = 1e18;

    /**
     * @dev Approve the RewardsManager to manage the reservoir's token funds
     */
    function approveRewardsManager() external override onlyGovernor {
        graphToken().approve(address(rewardsManager()), MAX_UINT256);
    }

    /**
     * @dev Get accumulated total rewards on this layer at a particular block
     * @param _blocknum Block number at which to calculate rewards
     * @return Accumulated total rewards on this layer
     */
    function getAccumulatedRewards(uint256 _blocknum) public view override returns (uint256) {
        // R(t) = R(t0) + (DeltaR(t, t0))
        return accumulatedLayerRewards + getNewRewards(_blocknum);
    }

    /**
     * @dev Get new total rewards on this layer at a particular block, since the last drip event.
     * Must be implemented by the reservoir on each layer.
     * @param _blocknum Block number at which to calculate rewards
     * @return New total rewards on this layer since the last drip
     */
    function getNewRewards(uint256 _blocknum) public view virtual override returns (uint256);

    /**
     * @dev Raises _x to the power of _n with scaling factor of _base.
     * Based on: https://github.com/makerdao/dss/blob/master/src/pot.sol#L81
     * @param _x Base of the exponentiation
     * @param _n Exponent
     * @param _base Scaling factor
     * @return Exponential of _n with base _x
     */
    function _pow(
        uint256 _x,
        uint256 _n,
        uint256 _base
    ) internal pure returns (uint256) {
        uint256 z;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            switch _x
            case 0 {
                switch _n
                case 0 {
                    z := _base
                }
                default {
                    z := 0
                }
            }
            default {
                switch mod(_n, 2)
                case 0 {
                    z := _base
                }
                default {
                    z := _x
                }
                let half := div(_base, 2) // for rounding.
                for {
                    _n := div(_n, 2)
                } _n {
                    _n := div(_n, 2)
                } {
                    let xx := mul(_x, _x)
                    if iszero(eq(div(xx, _x), _x)) {
                        revert(0, 0)
                    }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) {
                        revert(0, 0)
                    }
                    _x := div(xxRound, _base)
                    if mod(_n, 2) {
                        let zx := mul(z, _x)
                        if and(iszero(iszero(_x)), iszero(eq(div(zx, _x), z))) {
                            revert(0, 0)
                        }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) {
                            revert(0, 0)
                        }
                        z := div(zxRound, _base)
                    }
                }
            }
        }
        return z;
    }
}
