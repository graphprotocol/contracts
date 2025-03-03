// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { DataService } from "../../../contracts/data-service/DataService.sol";
import { IGraphPayments } from "./../../../contracts/interfaces/IGraphPayments.sol";

contract DataServiceBase is DataService {
    uint32 public constant DELEGATION_RATIO = 100;
    uint256 public constant PROVISION_TOKENS_MIN = 50;
    uint256 public constant PROVISION_TOKENS_MAX = 5000;
    uint32 public constant VERIFIER_CUT_MIN = 5;
    uint32 public constant VERIFIER_CUT_MAX = 100000;
    uint64 public constant THAWING_PERIOD_MIN = 15;
    uint64 public constant THAWING_PERIOD_MAX = 76;

    constructor(address controller) DataService(controller) initializer {
        __DataService_init();
    }

    function register(address serviceProvider, bytes calldata data) external {}

    function acceptProvisionPendingParameters(address serviceProvider, bytes calldata data) external {}

    function startService(address serviceProvider, bytes calldata data) external {}

    function stopService(address serviceProvider, bytes calldata data) external {}

    function collect(
        address serviceProvider,
        IGraphPayments.PaymentTypes feeType,
        bytes calldata data
    ) external returns (uint256) {}

    function slash(address serviceProvider, bytes calldata data) external {}

    function setDelegationRatio(uint32 ratio) external {
        _setDelegationRatio(ratio);
    }

    function setProvisionTokensRange(uint256 min, uint256 max) external {
        _setProvisionTokensRange(min, max);
    }

    function setVerifierCutRange(uint32 min, uint32 max) external {
        _setVerifierCutRange(min, max);
    }

    function setThawingPeriodRange(uint64 min, uint64 max) external {
        _setThawingPeriodRange(min, max);
    }

    function checkProvisionTokens(address serviceProvider) external view {
        _checkProvisionTokens(serviceProvider);
    }

    function checkProvisionParameters(address serviceProvider, bool pending) external view {
        _checkProvisionParameters(serviceProvider, pending);
    }

    function acceptProvisionParameters(address serviceProvider) external {
        _acceptProvisionParameters(serviceProvider);
    }
}
