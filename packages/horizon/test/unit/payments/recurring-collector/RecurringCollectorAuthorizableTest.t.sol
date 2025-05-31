// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IAuthorizable } from "../../../../contracts/interfaces/IAuthorizable.sol";
import { RecurringCollector } from "../../../../contracts/payments/collectors/RecurringCollector.sol";

import { AuthorizableTest } from "../../../unit/utilities/Authorizable.t.sol";
import { RecurringCollectorControllerMock } from "./RecurringCollectorControllerMock.t.sol";

contract RecurringCollectorAuthorizableTest is AuthorizableTest {
    function newAuthorizable(uint256 thawPeriod) public override returns (IAuthorizable) {
        return
            new RecurringCollector(
                "RecurringCollector",
                "1",
                address(new RecurringCollectorControllerMock(address(1))),
                thawPeriod
            );
    }
}
