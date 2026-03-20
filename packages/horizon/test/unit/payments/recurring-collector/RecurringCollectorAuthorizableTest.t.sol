// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAuthorizable } from "@graphprotocol/interfaces/contracts/horizon/IAuthorizable.sol";
import { RecurringCollector } from "../../../../contracts/payments/collectors/RecurringCollector.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import { AuthorizableTest } from "../../../unit/utilities/Authorizable.t.sol";
import { InvalidControllerMock } from "../../mocks/InvalidControllerMock.t.sol";

contract RecurringCollectorAuthorizableTest is AuthorizableTest {
    address internal _proxyAdmin;

    function newAuthorizable(uint256 thawPeriod) public override returns (IAuthorizable) {
        RecurringCollector implementation = new RecurringCollector(address(new InvalidControllerMock()), thawPeriod);
        address proxyAdminOwner = makeAddr("proxyAdmin");
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            proxyAdminOwner,
            abi.encodeCall(RecurringCollector.initialize, ("RecurringCollector", "1"))
        );
        // TransparentUpgradeableProxy deploys a ProxyAdmin contract — that's the address to exclude
        _proxyAdmin = address(uint160(uint256(vm.load(address(proxy), ERC1967Utils.ADMIN_SLOT))));
        return IAuthorizable(address(proxy));
    }

    function assumeValidFuzzAddress(address addr) internal override {
        super.assumeValidFuzzAddress(addr);
        vm.assume(addr != _proxyAdmin);
    }
}
