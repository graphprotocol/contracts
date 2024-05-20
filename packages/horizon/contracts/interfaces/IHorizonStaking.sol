// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.6.12 <0.9.0;
pragma abicoder v2;

import { IHorizonStakingBase } from "./IHorizonStakingBase.sol";
import { IHorizonStakingExtension } from "./IHorizonStakingExtension.sol";

interface IHorizonStaking is IHorizonStakingBase, IHorizonStakingExtension {}
