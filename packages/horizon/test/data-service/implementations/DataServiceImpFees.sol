// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { DataService } from "../../../contracts/data-service/DataService.sol";
import { DataServiceFees } from "../../../contracts/data-service/extensions/DataServiceFees.sol";
import { IGraphPayments } from "./../../../contracts/interfaces/IGraphPayments.sol";

contract DataServiceImpFees is DataServiceFees {
    uint256 public constant STAKE_TO_FEES_RATIO = 1000;
    uint256 public constant LOCK_DURATION = 1 minutes;

    constructor(address controller) DataService(controller) initializer {
        __DataService_init();
    }

    function register(address serviceProvider, bytes calldata data) external {}

    function acceptProvision(address serviceProvider, bytes calldata data) external {}

    function startService(address serviceProvider, bytes calldata data) external {}

    function stopService(address serviceProvider, bytes calldata data) external {}

    function collect(address serviceProvider, IGraphPayments.PaymentTypes, bytes calldata data) external returns (uint256) {
        uint256 amount = abi.decode(data, (uint256));
        _releaseStake(serviceProvider, 0);
        _lockStake(serviceProvider, amount * STAKE_TO_FEES_RATIO, block.timestamp + LOCK_DURATION);
    }

    function lockStake(address serviceProvider, uint256 amount) external {
        _lockStake(serviceProvider, amount * STAKE_TO_FEES_RATIO, block.timestamp + LOCK_DURATION);
    }

    function slash(address serviceProvider, bytes calldata data) external {}
}
