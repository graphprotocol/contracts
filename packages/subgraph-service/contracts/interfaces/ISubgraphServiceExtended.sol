// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { ISubgraphService } from "./ISubgraphService.sol";
import { ISubgraphServiceExtension } from "./ISubgraphServiceExtension.sol";

interface ISubgraphServiceExtended is ISubgraphService, ISubgraphServiceExtension {}
