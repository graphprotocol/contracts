// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.6.12 <0.8.0;
pragma abicoder v2;

import { IStaking } from "./IStaking.sol";
import { IL1StakingBase } from "./IL1StakingBase.sol";

/**
 * @title Interface for the L1 Staking contract
 * @notice This is the interface that should be used when interacting with the L1 Staking contract.
 * It extends the IStaking interface with the functions that are specific to L1, adding the transfer tools
 * to send stake and delegation to L2.
 * @dev Note that L1Staking doesn't actually inherit this interface. This is because of
 * the custom setup of the Staking contract where part of the functionality is implemented
 * in a separate contract (StakingExtension) to which calls are delegated through the fallback function.
 */
interface IL1Staking is IStaking, IL1StakingBase {
    // Nothing to see here
}
