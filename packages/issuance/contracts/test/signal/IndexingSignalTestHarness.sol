// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.33;

import { IndexingSignal } from "../../signal/IndexingSignal.sol";

/**
 * @title IndexingSignalTestHarness
 * @notice Exposes internal functions for white-box testing.
 */
contract IndexingSignalTestHarness is IndexingSignal {
    constructor(
        address graphToken,
        address rewardsManager,
        address curation
    ) IndexingSignal(graphToken, rewardsManager, curation) {}
}
