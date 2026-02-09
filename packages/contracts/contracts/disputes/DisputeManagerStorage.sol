// SPDX-License-Identifier: GPL-2.0-or-later

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable named-parameters-mapping

pragma solidity ^0.7.6;

import { Managed } from "../governance/Managed.sol";

import { IDisputeManager } from "@graphprotocol/interfaces/contracts/contracts/disputes/IDisputeManager.sol";

/**
 * @title Dispute Manager Storage V1
 * @author Edge & Node
 * @notice Storage contract for the Dispute Manager
 */
contract DisputeManagerV1Storage is Managed {
    // -- State --

    /// @dev Domain separator for EIP-712 signature verification
    bytes32 internal DOMAIN_SEPARATOR; // solhint-disable-line var-name-mixedcase

    /// @notice The arbitrator is solely in control of arbitrating disputes
    address public arbitrator;

    /// @notice Minimum deposit required to create a Dispute
    uint256 public minimumDeposit;

    // -- Slot 0xf
    /// @notice Percentage of indexer slashed funds to assign as a reward to fisherman in successful dispute
    /// Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public fishermanRewardPercentage;

    /// @notice Percentage of indexer stake to slash on disputes
    /// Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public qrySlashingPercentage;
    /// @notice Percentage of indexer stake to slash on disputes
    uint32 public idxSlashingPercentage;

    // -- Slot 0x10
    /// @notice Disputes created : disputeID => Dispute
    /// @dev disputeID - check creation functions to see how disputeID is built
    mapping(bytes32 => IDisputeManager.Dispute) public disputes;
}
