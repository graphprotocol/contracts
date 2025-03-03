// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;

interface IL2StakingTypes {
    /// @dev Message codes for the L1 -> L2 bridge callhook
    enum L1MessageCodes {
        RECEIVE_INDEXER_STAKE_CODE,
        RECEIVE_DELEGATION_CODE
    }

    /// @dev Encoded message struct when receiving indexer stake through the bridge
    struct ReceiveIndexerStakeData {
        address indexer;
    }

    /// @dev Encoded message struct when receiving delegation through the bridge
    struct ReceiveDelegationData {
        address indexer;
        address delegator;
    }
}
