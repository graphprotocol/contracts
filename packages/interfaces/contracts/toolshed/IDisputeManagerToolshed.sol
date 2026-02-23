// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.22;

import { IDisputeManager } from "../subgraph-service/IDisputeManager.sol";
import { IOwnable } from "./internal/IOwnable.sol";

/**
 * @title IDisputeManagerToolshed
 * @author Edge & Node
 * @notice Aggregate interface for DisputeManager TypeScript type generation.
 * @dev Combines all DisputeManager interfaces into a single artifact for Wagmi and ethers
 * type generation. Not intended for use in Solidity code.
 */
interface IDisputeManagerToolshed is IDisputeManager, IOwnable {}
