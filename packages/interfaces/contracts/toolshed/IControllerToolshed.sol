// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || 0.8.27;

// solhint-disable use-natspec

import { IController } from "../contracts/governance/IController.sol";
import { IGoverned } from "../contracts/governance/IGoverned.sol";

interface IControllerToolshed is IController, IGoverned {}
