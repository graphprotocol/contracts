// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "../governance/Managed.sol";

/**
 * @dev Base storage variables for the Reservoir on both layers
 */
contract ReservoirV1Storage is Managed {
    // Relative increase of the total supply per block, plus 1, expressed in fixed point at 1e18.
    uint256 public issuanceRate;
    // Accumulated total rewards on the corresponding layer (L1 or L2)
    uint256 public accumulatedLayerRewards;
    // Last block at which rewards when updated, i.e. block at which the last drip happened or was received
    uint256 public lastRewardsUpdateBlock;
    // Base value for token issuance, set initially to GRT supply and afterwards using accumulated rewards to update
    uint256 public issuanceBase;
}
