// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { IHorizonStakingTypes } from "./internal/IHorizonStakingTypes.sol";
import { IHorizonStakingMain } from "./internal/IHorizonStakingMain.sol";
import { IHorizonStakingExtension } from "./internal/IHorizonStakingExtension.sol";

interface IHorizonStaking is IHorizonStakingTypes, IHorizonStakingMain, IHorizonStakingExtension {}
