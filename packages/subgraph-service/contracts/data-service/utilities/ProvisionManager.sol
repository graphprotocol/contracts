// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";
import { IDataService } from "../IDataService.sol";

import { GraphDirectory } from "../GraphDirectory.sol";
import { ProvisionManagerV1Storage } from "./ProvisionManagerStorage.sol";

import { ProvisionGetter } from "../libraries/ProvisionGetter.sol";
import { UintRange } from "../libraries/UintRange.sol";

abstract contract ProvisionManager is GraphDirectory, ProvisionManagerV1Storage {
    using ProvisionGetter for IHorizonStaking;
    using UintRange for uint256;

    error ProvisionManagerInvalidProvisionTokens(
        uint256 tokens,
        uint256 minimumProvisionTokens,
        uint256 maximumProvisionTokens
    );
    error ProvisionManagerInvalidVerifierCut(
        uint256 verifierCut,
        uint256 minimumVerifierCut,
        uint256 maximumVerifierCut
    );
    error ProvisionManagerInvalidThawingPeriod(
        uint64 thawingPeriod,
        uint64 minimumThawingPeriod,
        uint64 maximumThawingPeriod
    );
    error ProvisionManagerNotAuthorized(address caller, address serviceProvider, address service);

    modifier onlyProvisionAuthorized(address serviceProvider) {
        if (!GRAPH_STAKING.isAuthorized(msg.sender, serviceProvider, address(this))) {
            revert ProvisionManagerNotAuthorized(msg.sender, serviceProvider, address(this));
        }
        _;
    }

    constructor() {
        minimumProvisionTokens = type(uint256).min;
        maximumProvisionTokens = type(uint256).max;

        minimumThawingPeriod = type(uint64).min;
        maximumThawingPeriod = type(uint64).max;

        minimumVerifierCut = type(uint32).min;
        maximumVerifierCut = type(uint32).max;
    }

    function _checkAndAcceptProvision(address _serviceProvider) internal virtual {
        _checkProvisionParameters(_serviceProvider);
        GRAPH_STAKING.acceptProvision(_serviceProvider);
    }

    // -- Provision Parameters: setters --
    function _setProvisionTokensRange(uint256 _min, uint256 _max) internal {
        minimumProvisionTokens = _min;
        maximumProvisionTokens = _max;
    }

    function _setVerifierCutRange(uint32 _min, uint32 _max) internal {
        minimumVerifierCut = _min;
        maximumVerifierCut = _max;
    }

    function _setThawingPeriodRange(uint64 _min, uint64 _max) internal {
        minimumThawingPeriod = _min;
        maximumThawingPeriod = _max;
    }

    /// @notice Checks if the service provider has a valid provision for the data service in the staking contract
    /// @param _serviceProvider The address of the service provider
    function _checkProvisionParameters(address _serviceProvider) internal view virtual {
        IHorizonStaking.Provision memory provision = _getProvision(_serviceProvider);

        (uint256 provisionTokensMin, uint256 provisionTokensMax) = _getProvisionTokensRange();
        if (!provision.tokens.isInRange(provisionTokensMin, provisionTokensMax)) {
            revert ProvisionManagerInvalidProvisionTokens(provision.tokens, provisionTokensMin, provisionTokensMax);
        }

        (uint64 thawingPeriodMin, uint64 thawingPeriodMax) = _getThawingPeriodRange();
        if (!uint256(provision.thawingPeriod).isInRange(thawingPeriodMin, thawingPeriodMax)) {
            revert ProvisionManagerInvalidThawingPeriod(provision.thawingPeriod, thawingPeriodMin, thawingPeriodMax);
        }

        (uint32 verifierCutMin, uint32 verifierCutMax) = _getVerifierCutRange();
        if (!uint256(provision.maxVerifierCut).isInRange(verifierCutMin, verifierCutMax)) {
            revert ProvisionManagerInvalidVerifierCut(provision.maxVerifierCut, verifierCutMin, verifierCutMax);
        }
    }

    // -- Provision Parameters: getters --
    function _getProvisionTokensRange() internal view virtual returns (uint256 min, uint256 max) {
        return (minimumProvisionTokens, maximumProvisionTokens);
    }

    function _getThawingPeriodRange() internal view virtual returns (uint64 min, uint64 max) {
        return (minimumThawingPeriod, maximumThawingPeriod);
    }

    function _getVerifierCutRange() internal view virtual returns (uint32 min, uint32 max) {
        return (minimumVerifierCut, maximumVerifierCut);
    }

    function _getProvision(address _serviceProvider) internal view returns (IHorizonStaking.Provision memory) {
        return GRAPH_STAKING.get(_serviceProvider);
    }
}
