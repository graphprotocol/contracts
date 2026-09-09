// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { IPaymentsEscrow } from "../horizon/IPaymentsEscrow.sol";

/**
 * @title IPaymentsEscrowToolshed
 * @author Edge & Node
 * @notice Aggregate interface for PaymentsEscrow TypeScript type generation.
 * @dev Combines all PaymentsEscrow interfaces into a single artifact for Wagmi and ethers
 * type generation. Not intended for use in Solidity code.
 */
interface IPaymentsEscrowToolshed is IPaymentsEscrow {}
