// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || 0.8.27;

import { IHorizonStaking } from "../horizon/IHorizonStaking.sol";
import { IMulticall } from "../horizon/internal/IMulticall.sol";

interface IHorizonStakingToolshed is IHorizonStaking, IMulticall {}
