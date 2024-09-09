// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { IHorizonStakingTypes } from "./internal/IHorizonStakingTypes.sol";
import { IHorizonStakingMain } from "./internal/IHorizonStakingMain.sol";
import { IHorizonStakingBase } from "./internal/IHorizonStakingBase.sol";
import { IHorizonStakingExtension } from "./internal/IHorizonStakingExtension.sol";

/**
 * @title Complete interface for the Horizon Staking contract
 * @notice This interface exposes all functions implemented by the {HorizonStaking} contract and its extension
 * {HorizonStakingExtension} as well as the custom data types used by the contract.
 * @dev Use this interface to interact with the Horizon Staking contract.
 */
interface IHorizonStaking is IHorizonStakingTypes, IHorizonStakingBase, IHorizonStakingMain, IHorizonStakingExtension {}
