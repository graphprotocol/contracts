// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { DataService } from "../../../contracts/data-service/DataService.sol";
import { DataServicePausable } from "../../../contracts/data-service/extensions/DataServicePausable.sol";
import { IGraphPayments } from "./../../../contracts/interfaces/IGraphPayments.sol";

contract DataServiceImpPausable is DataServicePausable {
    uint32 public constant DELEGATION_RATIO = 100;
    uint256 public constant PROVISION_TOKENS_MIN = 50;
    uint256 public constant PROVISION_TOKENS_MAX = 5000;
    uint32 public constant VERIFIER_CUT_MIN = 5;
    uint32 public constant VERIFIER_CUT_MAX = 100000;
    uint64 public constant THAWING_PERIOD_MIN = 15;
    uint64 public constant THAWING_PERIOD_MAX = 76;

    event PausedProtectedFn();
    event UnpausedProtectedFn();

    constructor(address controller) DataService(controller) initializer {
        __DataService_init();
    }

    function register(address serviceProvider, bytes calldata data) external {}

    function acceptProvisionPendingParameters(address serviceProvider, bytes calldata data) external {}

    function startService(address serviceProvider, bytes calldata data) external {}

    function stopService(address serviceProvider, bytes calldata data) external {}

    function collect(address serviceProvider, IGraphPayments.PaymentTypes feeType, bytes calldata data) external returns (uint256) {}

    function slash(address serviceProvider, bytes calldata data) external {}

    function setPauseGuardian(address pauseGuardian, bool allowed) external {
        _setPauseGuardian(pauseGuardian, allowed);
    }

    function pausedProtectedFn() external whenNotPaused {
        emit PausedProtectedFn();
    }

    function unpausedProtectedFn() external whenPaused {
        emit UnpausedProtectedFn();
    }
}
