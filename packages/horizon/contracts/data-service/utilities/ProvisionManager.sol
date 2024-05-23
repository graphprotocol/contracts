// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IHorizonStaking } from "../../interfaces/IHorizonStaking.sol";

import { ProvisionGetter } from "../libraries/ProvisionGetter.sol";
import { UintRange } from "../../libraries/UintRange.sol";

import { GraphDirectory } from "../GraphDirectory.sol";
import { ProvisionManagerV1Storage } from "./ProvisionManagerStorage.sol";

abstract contract ProvisionManager is GraphDirectory, ProvisionManagerV1Storage {
    using ProvisionGetter for IHorizonStaking;
    using UintRange for uint256;

    error ProvisionManagerInvalidValue(bytes message, uint256 value, uint256 min, uint256 max);
    error ProvisionManagerNotAuthorized(address caller, address serviceProvider, address service);

    modifier onlyProvisionAuthorized(address serviceProvider) {
        if (!_graphStaking().isAuthorized(msg.sender, serviceProvider, address(this))) {
            revert ProvisionManagerNotAuthorized(msg.sender, serviceProvider, address(this));
        }
        _;
    }

    modifier onlyValidProvision(address serviceProvider) virtual {
        _checkProvisionTokens(serviceProvider);
        _checkProvisionDelegationRatio(serviceProvider);
        _checkProvisionParameters(serviceProvider, false);
        _;
    }

    constructor() {
        minimumProvisionTokens = type(uint256).min;
        maximumProvisionTokens = type(uint256).max;

        minimumDelegationRatio = type(uint32).min;
        maximumDelegationRatio = type(uint32).max;

        minimumThawingPeriod = type(uint64).min;
        maximumThawingPeriod = type(uint64).max;

        minimumVerifierCut = type(uint32).min;
        maximumVerifierCut = type(uint32).max;
    }

    /**
     * @notice Verifies and accepts the provision of a service provider in the {Graph Horizon staking
     * contract}.
     * @dev Checks the pending provision parameters, not the current ones.
     *
     * Emits a {ProvisionAccepted} event.
     *
     * @param _serviceProvider The address of the service provider.
     */
    function _acceptProvisionParameters(address _serviceProvider) internal virtual {
        _checkProvisionParameters(_serviceProvider, true);
        _graphStaking().acceptProvisionParameters(_serviceProvider);
    }

    // -- Provision Parameters: setters --
    function _setProvisionTokensRange(uint256 _min, uint256 _max) internal {
        minimumProvisionTokens = _min;
        maximumProvisionTokens = _max;
    }

    function _setDelegationRatioRange(uint32 _min, uint32 _max) internal {
        minimumDelegationRatio = _min;
        maximumDelegationRatio = _max;
    }

    function _setVerifierCutRange(uint32 _min, uint32 _max) internal {
        minimumVerifierCut = _min;
        maximumVerifierCut = _max;
    }

    function _setThawingPeriodRange(uint64 _min, uint64 _max) internal {
        minimumThawingPeriod = _min;
        maximumThawingPeriod = _max;
    }

    function _checkProvisionTokens(address _serviceProvider) internal view virtual {
        IHorizonStaking.Provision memory provision = _getProvision(_serviceProvider);
        _checkValueInRange(provision.tokens, minimumProvisionTokens, maximumProvisionTokens, "tokens");
    }

    function _checkProvisionDelegationRatio(address _serviceProvider) internal view virtual {
        IHorizonStaking.Provision memory provision = _getProvision(_serviceProvider);
        uint256 delegatedTokens = _graphStaking().getDelegatedTokensAvailable(_serviceProvider, address(this));

        (uint32 delegationRatioMin, uint32 delegationRatioMax) = _getDelegationRatioRange();
        uint256 delegationRatioToCheck = uint32(delegatedTokens / (provision.tokens - provision.tokensThawing));
        _checkValueInRange(delegationRatioToCheck, delegationRatioMin, delegationRatioMax, "delegationRatio");
    }

    function _checkProvisionParameters(address _serviceProvider, bool _checkPending) internal view virtual {
        IHorizonStaking.Provision memory provision = _getProvision(_serviceProvider);

        (uint64 thawingPeriodMin, uint64 thawingPeriodMax) = _getThawingPeriodRange();
        uint64 thawingPeriodToCheck = _checkPending ? provision.thawingPeriodPending : provision.thawingPeriod;
        _checkValueInRange(thawingPeriodToCheck, thawingPeriodMin, thawingPeriodMax, "thawingPeriod");

        (uint32 verifierCutMin, uint32 verifierCutMax) = _getVerifierCutRange();
        uint32 maxVerifierCutToCheck = _checkPending ? provision.maxVerifierCutPending : provision.maxVerifierCut;
        _checkValueInRange(maxVerifierCutToCheck, verifierCutMin, verifierCutMax, "maxVerifierCut");
    }

    // -- Provision Parameters: getters --
    function _getProvisionTokensRange() internal view virtual returns (uint256 min, uint256 max) {
        return (minimumProvisionTokens, maximumProvisionTokens);
    }

    function _getDelegationRatioRange() internal view virtual returns (uint32 min, uint32 max) {
        return (minimumDelegationRatio, maximumDelegationRatio);
    }

    function _getThawingPeriodRange() internal view virtual returns (uint64 min, uint64 max) {
        return (minimumThawingPeriod, maximumThawingPeriod);
    }

    function _getVerifierCutRange() internal view virtual returns (uint32 min, uint32 max) {
        return (minimumVerifierCut, maximumVerifierCut);
    }

    function _getProvision(address _serviceProvider) internal view returns (IHorizonStaking.Provision memory) {
        return _graphStaking().get(_serviceProvider);
    }

    function _checkValueInRange(uint256 _value, uint256 _min, uint256 _max, bytes memory _revertMessage) private pure {
        if (!_value.isInRange(_min, _max)) {
            revert ProvisionManagerInvalidValue(_revertMessage, _value, _min, _max);
        }
    }
}
