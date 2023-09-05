// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.6.12 <0.8.0;
pragma abicoder v2;

import { IStakingBase } from "./IStakingBase.sol";
import { IStakingExtension } from "./IStakingExtension.sol";
import { IMulticall } from "../base/IMulticall.sol";
import { IManaged } from "../governance/IManaged.sol";

/**
 * @title Interface for the Staking contract
 * @notice This is the interface that should be used when interacting with the Staking contract.
 * @dev Note that Staking doesn't actually inherit this interface. This is because of
 * the custom setup of the Staking contract where part of the functionality is implemented
 * in a separate contract (StakingExtension) to which calls are delegated through the fallback function.
 */
interface IStaking is IStakingBase, IStakingExtension, IMulticall, IManaged {
    // Nothing to see here
}
