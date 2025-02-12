// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { DataServiceBase } from "./DataServiceBase.sol";

contract DataServiceOverride is DataServiceBase {
    constructor(address controller) DataServiceBase(controller) initializer {
        __DataService_init();
    }

    function _getProvisionTokensRange() internal pure override returns (uint256, uint256) {
        return (PROVISION_TOKENS_MIN, PROVISION_TOKENS_MAX);
    }

    function _getVerifierCutRange() internal pure override returns (uint32, uint32) {
        return (VERIFIER_CUT_MIN, VERIFIER_CUT_MAX);
    }

    function _getThawingPeriodRange() internal pure override returns (uint64, uint64) {
        return (THAWING_PERIOD_MIN, THAWING_PERIOD_MAX);
    }

    function _checkProvisionTokens(address _serviceProvider) internal pure override {}
    function _checkProvisionParameters(address _serviceProvider, bool pending) internal pure override {}
}
