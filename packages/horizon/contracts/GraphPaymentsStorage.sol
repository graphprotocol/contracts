// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphPayments } from "./interfaces/IGraphPayments.sol";

contract GraphPaymentsStorageV1Storage {
    // Authorized collectors
    mapping(address sender => mapping(address collector => uint256 thawEndTimestamp)) public authorizedCollectors;

    // The maximum thawing period (in seconds) for removing collector authorization
    // This is a precautionary measure to avoid inadvertedly locking collectors for too long
    uint256 public constant MAX_THAWING_PERIOD = 90 days;

    // Thawing period for authorized collectors
    uint256 public immutable revokeCollectorThawingPeriod;

    // The graph protocol payment cut
    uint256 public immutable protocolPaymentCut;
}
