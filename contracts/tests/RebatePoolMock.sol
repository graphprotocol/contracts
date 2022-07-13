// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import "../staking/libs/Rebates.sol";
import "../staking/libs/Cobbs.sol";

// Mock contract used for testing rebates
contract RebatePoolMock {
    using Rebates for Rebates.Pool;

    // -- State --

    uint32 public alphaNumerator;
    uint32 public alphaDenominator;

    Rebates.Pool public rebatePool;

    // -- Events --

    event Redeemed(uint256 value);

    // Set the alpha for rebates
    function setRebateRatio(uint32 _alphaNumerator, uint32 _alphaDenominator) external {
        rebatePool.init(_alphaNumerator, _alphaDenominator);
    }

    // Add fees and stake to the rebate pool
    function add(uint256 _indexerFees, uint256 _indexerAllocatedStake) external {
        rebatePool.addToPool(_indexerFees, _indexerAllocatedStake);
    }

    // Remove rewards from rebate pool
    function pop(uint256 _indexerFees, uint256 _indexerAllocatedStake) external returns (uint256) {
        uint256 value = rebatePool.redeem(_indexerFees, _indexerAllocatedStake);
        emit Redeemed(value);
        return value;
    }

    // Stub to test the cobb-douglas formula directly
    function cobbDouglas(
        uint256 _totalRewards,
        uint256 _fees,
        uint256 _totalFees,
        uint256 _stake,
        uint256 _totalStake,
        uint32 _alphaNumerator,
        uint32 _alphaDenominator
    ) external pure returns (uint256) {
        if (_totalFees == 0 || _totalStake == 0) {
            return 0;
        }

        return
            LibCobbDouglas.cobbDouglas(
                _totalRewards,
                _fees,
                _totalFees,
                _stake,
                _totalStake,
                _alphaNumerator,
                _alphaDenominator
            );
    }
}
