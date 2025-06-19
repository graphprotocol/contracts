// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IAuthorizable } from "../../../../contracts/interfaces/IAuthorizable.sol";
import { RecurringCollector } from "../../../../contracts/payments/collectors/RecurringCollector.sol";

import { AuthorizableTest } from "../../../unit/utilities/Authorizable.t.sol";
import { InvalidControllerMock } from "../../mocks/InvalidControllerMock.t.sol";

contract RecurringCollectorAuthorizableTest is AuthorizableTest {
    function newAuthorizable(uint256 thawPeriod) public override returns (IAuthorizable) {
        return new RecurringCollector("RecurringCollector", "1", address(new InvalidControllerMock()), thawPeriod);
    }
}
