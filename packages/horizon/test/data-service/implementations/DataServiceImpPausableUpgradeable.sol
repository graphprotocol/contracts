// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { DataService } from "../../../contracts/data-service/DataService.sol";
import { DataServicePausableUpgradeable } from "../../../contracts/data-service/extensions/DataServicePausableUpgradeable.sol";
import { IGraphPayments } from "./../../../contracts/interfaces/IGraphPayments.sol";

contract DataServiceImpPausableUpgradeable is DataServicePausableUpgradeable {
    constructor(address controller) DataService(controller) {
        _disableInitializers();
    }

    function initialize() external initializer {
        __DataService_init();
        __DataServicePausable_init();
    }

    function register(address serviceProvider, bytes calldata data) external {}

    function acceptProvision(address serviceProvider, bytes calldata data) external {}

    function startService(address serviceProvider, bytes calldata data) external {}

    function stopService(address serviceProvider, bytes calldata data) external {}

    function collect(address serviceProvider, IGraphPayments.PaymentTypes feeType, bytes calldata data) external {}

    function slash(address serviceProvider, bytes calldata data) external {}

    function controller() external view returns (address) {
        return address(_graphController());
    }
}
