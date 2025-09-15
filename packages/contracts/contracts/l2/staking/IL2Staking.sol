// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.6.12 <0.8.0;
pragma abicoder v2;

import { IStaking } from "../../staking/IStaking.sol";
import { IL2StakingBase } from "./IL2StakingBase.sol";
import { IL2StakingTypes } from "./IL2StakingTypes.sol";

/**
 * @title Interface for the L2 Staking contract
 * @notice This is the interface that should be used when interacting with the L2 Staking contract.
 * It extends the IStaking interface with the functions that are specific to L2, adding the callhook receiver
 * to receive transferred stake and delegation from L1.
 * @dev Note that L2Staking doesn't actually inherit this interface. This is because of
 * the custom setup of the Staking contract where part of the functionality is implemented
 * in a separate contract (StakingExtension) to which calls are delegated through the fallback function.
 */
interface IL2Staking is IStaking, IL2StakingBase, IL2StakingTypes {}
