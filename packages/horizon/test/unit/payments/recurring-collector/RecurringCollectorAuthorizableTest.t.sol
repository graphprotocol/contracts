// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IAuthorizable } from "@graphprotocol/interfaces/contracts/horizon/IAuthorizable.sol";
import { RecurringCollector } from "../../../../contracts/payments/collectors/RecurringCollector.sol";

import { AuthorizableTest } from "../../../unit/utilities/Authorizable.t.sol";
import { InvalidControllerMock } from "../../mocks/InvalidControllerMock.t.sol";

contract RecurringCollectorAuthorizableTest is AuthorizableTest {
    function newAuthorizable(uint256 thawPeriod) public override returns (IAuthorizable) {
        return new RecurringCollector("RecurringCollector", "1", address(new InvalidControllerMock()), thawPeriod);
    }
}
