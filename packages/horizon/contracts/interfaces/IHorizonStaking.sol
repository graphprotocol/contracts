// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { IHorizonStakingBase } from "./IHorizonStakingBase.sol";
import { IHorizonStakingExtension } from "./IHorizonStakingExtension.sol";

interface IHorizonStaking is IHorizonStakingBase, IHorizonStakingExtension {}
