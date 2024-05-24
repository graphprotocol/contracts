// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { IHorizonStakingTypes } from "./IHorizonStakingTypes.sol";
import { IHorizonStakingMain } from "./IHorizonStakingMain.sol";
import { IHorizonStakingExtension } from "./IHorizonStakingExtension.sol";

interface IHorizonStaking is IHorizonStakingTypes, IHorizonStakingMain, IHorizonStakingExtension {}
