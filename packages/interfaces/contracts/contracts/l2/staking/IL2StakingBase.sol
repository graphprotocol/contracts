// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events

import { ICallhookReceiver } from "../../gateway/ICallhookReceiver.sol";

/**
 * @title Base interface for the L2Staking contract.
 * @author Edge & Node
 * @notice This interface is used to define the callhook receiver interface that is implemented by L2Staking.
 * @dev Note it includes only the L2-specific functionality, not the full IStaking interface.
 */
interface IL2StakingBase is ICallhookReceiver {
    /**
     * @notice Emitted when transferred delegation is returned to a delegator
     * @param indexer Address of the indexer
     * @param delegator Address of the delegator
     * @param amount Amount of delegation returned
     */
    event TransferredDelegationReturnedToDelegator(address indexed indexer, address indexed delegator, uint256 amount);
}
