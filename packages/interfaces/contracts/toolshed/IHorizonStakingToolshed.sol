// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || 0.8.27;

// solhint-disable use-natspec

import { IHorizonStaking } from "../horizon/IHorizonStaking.sol";
import { IMulticall } from "../contracts/base/IMulticall.sol";

interface IHorizonStakingToolshed is IHorizonStaking, IMulticall {}
