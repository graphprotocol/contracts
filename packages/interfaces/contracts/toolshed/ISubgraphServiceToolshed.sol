// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { ISubgraphService } from "../subgraph-service/ISubgraphService.sol";
import { IOwnable } from "./internal/IOwnable.sol";
import { IPausable } from "./internal/IPausable.sol";
import { ILegacyAllocation } from "../subgraph-service/internal/ILegacyAllocation.sol";
import { IProvisionManager } from "./internal/IProvisionManager.sol";
import { IProvisionTracker } from "./internal/IProvisionTracker.sol";
import { IDataServicePausable } from "../data-service/IDataServicePausable.sol";
import { IMulticall } from "../contracts/base/IMulticall.sol";
import { IAllocationManager } from "../subgraph-service/internal/IAllocationManager.sol";

/**
 * @title ISubgraphServiceToolshed
 * @author Edge & Node
 * @notice Aggregate interface for SubgraphService TypeScript type generation.
 * @dev Combines all SubgraphService interfaces into a single artifact for Wagmi and ethers
 * type generation. Not intended for use in Solidity code.
 */
interface ISubgraphServiceToolshed is
    ISubgraphService,
    IAllocationManager,
    IOwnable,
    IPausable,
    IDataServicePausable,
    ILegacyAllocation,
    IProvisionManager,
    IProvisionTracker,
    IMulticall
{}
