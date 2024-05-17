// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.6.12 <0.9.0;

import { ICallhookReceiver } from "../../gateway/ICallhookReceiver.sol";

/**
 * @title Base interface for the L2Staking contract.
 * @notice This interface is used to define the callhook receiver interface that is implemented by L2Staking.
 * @dev Note it includes only the L2-specific functionality, not the full IStaking interface.
 */
interface IL2StakingBase is ICallhookReceiver {
    event TransferredDelegationReturnedToDelegator(address indexed indexer, address indexed delegator, uint256 amount);
}
