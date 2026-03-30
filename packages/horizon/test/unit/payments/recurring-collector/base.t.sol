// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorBaseTest is RecurringCollectorSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_TypeHashes() public view {
        // Verify the typehash constants are set
        assertTrue(_recurringCollector.RCA_TYPEHASH() != bytes32(0), "RCA typehash should be non-zero");
        assertTrue(_recurringCollector.RCAU_TYPEHASH() != bytes32(0), "RCAU typehash should be non-zero");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
