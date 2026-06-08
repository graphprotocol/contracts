// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || ^0.8.0;

import { IRewardsManager } from "../contracts/rewards/IRewardsManager.sol";
import { IRewardsManagerDeprecated } from "../contracts/rewards/IRewardsManagerDeprecated.sol";
import { IIssuanceTarget } from "../issuance/allocate/IIssuanceTarget.sol";

/**
 * @title IRewardsManagerToolshed
 * @author Edge & Node
 * @notice Aggregate interface for RewardsManager TypeScript type generation.
 * @dev Combines all RewardsManager interfaces into a single artifact for Wagmi and ethers
 * type generation. Not intended for use in Solidity code.
 */
interface IRewardsManagerToolshed is IRewardsManager, IIssuanceTarget, IRewardsManagerDeprecated {}
