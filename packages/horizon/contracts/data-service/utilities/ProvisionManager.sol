// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IHorizonStaking } from "../../interfaces/IHorizonStaking.sol";

import { UintRange } from "../../libraries/UintRange.sol";
import { PPMMath } from "../../libraries/PPMMath.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { GraphDirectory } from "../../utilities/GraphDirectory.sol";
import { ProvisionManagerV1Storage } from "./ProvisionManagerStorage.sol";

/**
 * @title ProvisionManager contract
 * @notice A helper contract that implements several provision management functions.
 * @dev Provides utilities to verify provision parameters are within an acceptable range. Each
 * parameter has an overridable setter and getter for the validity range, and a checker that reverts
 * if the parameter is out of range.
 * The parameters are:
 * - Provision parameters (thawing period and verifier cut)
 * - Provision tokens
 */
abstract contract ProvisionManager is Initializable, GraphDirectory, ProvisionManagerV1Storage {
    using UintRange for uint256;

    // Constants
    uint32 internal constant DEFAULT_MIN_VERIFIER_CUT = type(uint32).min;
    uint32 internal constant DEFAULT_MAX_VERIFIER_CUT = uint32(PPMMath.MAX_PPM);
    uint64 internal constant DEFAULT_MIN_THAWING_PERIOD = type(uint64).min;
    uint64 internal constant DEFAULT_MAX_THAWING_PERIOD = type(uint64).max;
    uint256 internal constant DEFAULT_MIN_PROVISION_TOKENS = type(uint256).min;
    uint256 internal constant DEFAULT_MAX_PROVISION_TOKENS = type(uint256).max;

    /**
     * @notice Emitted when the provision tokens range is set.
     * @param min The minimum allowed value for the provision tokens.
     * @param max The maximum allowed value for the provision tokens.
     */
    event ProvisionTokensRangeSet(uint256 min, uint256 max);

    /**
     * @notice Emitted when the delegation ratio is set.
     * @param ratio The delegation ratio
     */
    event DelegationRatioSet(uint32 ratio);

    /**
     * @notice Emitted when the verifier cut range is set.
     * @param min The minimum allowed value for the max verifier cut.
     * @param max The maximum allowed value for the max verifier cut.
     */
    event VerifierCutRangeSet(uint32 min, uint32 max);

    /**
     * @notice Emitted when the thawing period range is set.
     * @param min The minimum allowed value for the thawing period.
     * @param max The maximum allowed value for the thawing period.
     */
    event ThawingPeriodRangeSet(uint64 min, uint64 max);

    /**
     * @notice Thrown when a provision parameter is out of range.
     * @param message The error message.
     * @param value The value that is out of range.
     * @param min The minimum allowed value.
     * @param max The maximum allowed value.
     */
    error ProvisionManagerInvalidValue(bytes message, uint256 value, uint256 min, uint256 max);

    /**
     * @notice Thrown when attempting to set a range where min is greater than max.
     * @param min The minimum value.
     * @param max The maximum value.
     */
    error ProvisionManagerInvalidRange(uint256 min, uint256 max);

    /**
     * @notice Thrown when the caller is not authorized to manage the provision of a service provider.
     * @param caller The address of the caller.
     * @param serviceProvider The address of the service provider.
     */
    error ProvisionManagerNotAuthorized(address serviceProvider, address caller);

    /**
     * @notice Thrown when a provision is not found.
     * @param serviceProvider The address of the service provider.
     */
    error ProvisionManagerProvisionNotFound(address serviceProvider);

    /**
     * @notice Checks if the caller is authorized to manage the provision of a service provider.
     */
    modifier onlyAuthorizedForProvision(address serviceProvider) {
        require(
            _graphStaking().isAuthorized(msg.sender, serviceProvider, address(this)),
            ProvisionManagerNotAuthorized(serviceProvider, msg.sender)
        );
        _;
    }

    /**
     * @notice Checks if a provision of a service provider is valid according
     * to the parameter ranges established.
     */
    modifier onlyValidProvision(address serviceProvider) virtual {
        IHorizonStaking.Provision memory provision = _getProvision(serviceProvider);
        _checkProvisionTokens(provision);
        _checkProvisionParameters(provision, false);
        _;
    }

    /**
     * @notice Initializes the contract and any parent contracts.
     */
    // solhint-disable-next-line func-name-mixedcase
    function __ProvisionManager_init() internal onlyInitializing {
        __ProvisionManager_init_unchained();
    }

    /**
     * @notice Initializes the contract.
     * @dev All parameters set to their entire range as valid.
     */
    // solhint-disable-next-line func-name-mixedcase
    function __ProvisionManager_init_unchained() internal onlyInitializing {
        _setProvisionTokensRange(DEFAULT_MIN_PROVISION_TOKENS, DEFAULT_MAX_PROVISION_TOKENS);
        _setVerifierCutRange(DEFAULT_MIN_VERIFIER_CUT, DEFAULT_MAX_VERIFIER_CUT);
        _setThawingPeriodRange(DEFAULT_MIN_THAWING_PERIOD, DEFAULT_MAX_THAWING_PERIOD);
    }

    /**
     * @notice Verifies and accepts the provision parameters of a service provider in
     * the {HorizonStaking} contract.
     * @dev Checks the pending provision parameters, not the current ones.
     *
     * Emits a {ProvisionPendingParametersAccepted} event.
     *
     * @param _serviceProvider The address of the service provider.
     */
    function _acceptProvisionParameters(address _serviceProvider) internal {
        _checkProvisionParameters(_serviceProvider, true);
        _graphStaking().acceptProvisionParameters(_serviceProvider);
    }

    // -- setters --
    /**
     * @notice Sets the delegation ratio.
     * @param _ratio The delegation ratio to be set
     */
    function _setDelegationRatio(uint32 _ratio) internal {
        delegationRatio = _ratio;
        emit DelegationRatioSet(_ratio);
    }

    /**
     * @notice Sets the range for the provision tokens.
     * @param _min The minimum allowed value for the provision tokens.
     * @param _max The maximum allowed value for the provision tokens.
     */
    function _setProvisionTokensRange(uint256 _min, uint256 _max) internal {
        require(_min <= _max, ProvisionManagerInvalidRange(_min, _max));
        minimumProvisionTokens = _min;
        maximumProvisionTokens = _max;
        emit ProvisionTokensRangeSet(_min, _max);
    }

    /**
     * @notice Sets the range for the verifier cut.
     * @param _min The minimum allowed value for the max verifier cut.
     * @param _max The maximum allowed value for the max verifier cut.
     */
    function _setVerifierCutRange(uint32 _min, uint32 _max) internal {
        require(_min <= _max, ProvisionManagerInvalidRange(_min, _max));
        require(PPMMath.isValidPPM(_max), ProvisionManagerInvalidRange(_min, _max));
        minimumVerifierCut = _min;
        maximumVerifierCut = _max;
        emit VerifierCutRangeSet(_min, _max);
    }

    /**
     * @notice Sets the range for the thawing period.
     * @param _min The minimum allowed value for the thawing period.
     * @param _max The maximum allowed value for the thawing period.
     */
    function _setThawingPeriodRange(uint64 _min, uint64 _max) internal {
        require(_min <= _max, ProvisionManagerInvalidRange(_min, _max));
        minimumThawingPeriod = _min;
        maximumThawingPeriod = _max;
        emit ThawingPeriodRangeSet(_min, _max);
    }

    // -- checks --

    /**
     * @notice Checks if the provision tokens of a service provider are within the valid range.
     * @param _serviceProvider The address of the service provider.
     */
    function _checkProvisionTokens(address _serviceProvider) internal view virtual {
        IHorizonStaking.Provision memory provision = _getProvision(_serviceProvider);
        _checkProvisionTokens(provision);
    }

    /**
     * @notice Checks if the provision tokens of a service provider are within the valid range.
     * @param _provision The provision to check.
     */
    function _checkProvisionTokens(IHorizonStaking.Provision memory _provision) internal view virtual {
        _checkValueInRange(_provision.tokens, minimumProvisionTokens, maximumProvisionTokens, "tokens");
    }

    /**
     * @notice Checks if the provision parameters of a service provider are within the valid range.
     * @param _serviceProvider The address of the service provider.
     * @param _checkPending If true, checks the pending provision parameters.
     */
    function _checkProvisionParameters(address _serviceProvider, bool _checkPending) internal view virtual {
        IHorizonStaking.Provision memory provision = _getProvision(_serviceProvider);
        _checkProvisionParameters(provision, _checkPending);
    }

    /**
     * @notice Checks if the provision parameters of a service provider are within the valid range.
     * @param _provision The provision to check.
     * @param _checkPending If true, checks the pending provision parameters instead of the current ones.
     */
    function _checkProvisionParameters(
        IHorizonStaking.Provision memory _provision,
        bool _checkPending
    ) internal view virtual {
        (uint64 thawingPeriodMin, uint64 thawingPeriodMax) = _getThawingPeriodRange();
        uint64 thawingPeriodToCheck = _checkPending ? _provision.thawingPeriodPending : _provision.thawingPeriod;
        _checkValueInRange(thawingPeriodToCheck, thawingPeriodMin, thawingPeriodMax, "thawingPeriod");

        (uint32 verifierCutMin, uint32 verifierCutMax) = _getVerifierCutRange();
        uint32 maxVerifierCutToCheck = _checkPending ? _provision.maxVerifierCutPending : _provision.maxVerifierCut;
        _checkValueInRange(maxVerifierCutToCheck, verifierCutMin, verifierCutMax, "maxVerifierCut");
    }

    // -- getters --

    /**
     * @notice Gets the delegation ratio.
     * @return The delegation ratio
     */
    function _getDelegationRatio() internal view returns (uint32) {
        return delegationRatio;
    }

    /**
     * @notice Gets the range for the provision tokens.
     * @return min The minimum allowed value for the provision tokens.
     * @return max The maximum allowed value for the provision tokens.
     */
    function _getProvisionTokensRange() internal view virtual returns (uint256 min, uint256 max) {
        return (minimumProvisionTokens, maximumProvisionTokens);
    }

    /**
     * @notice  Gets the range for the thawing period.
     * @return min The minimum allowed value for the thawing period.
     * @return max The maximum allowed value for the thawing period.
     */
    function _getThawingPeriodRange() internal view virtual returns (uint64 min, uint64 max) {
        return (minimumThawingPeriod, maximumThawingPeriod);
    }

    /**
     * @notice Gets the range for the verifier cut.
     * @return min The minimum allowed value for the max verifier cut.
     * @return max The maximum allowed value for the max verifier cut.
     */
    function _getVerifierCutRange() internal view virtual returns (uint32 min, uint32 max) {
        return (minimumVerifierCut, maximumVerifierCut);
    }

    /**
     * @notice Gets a provision from the {HorizonStaking} contract.
     * @dev Requirements:
     * - The provision must exist.
     * @param _serviceProvider The address of the service provider.
     */
    function _getProvision(address _serviceProvider) internal view returns (IHorizonStaking.Provision memory) {
        IHorizonStaking.Provision memory provision = _graphStaking().getProvision(_serviceProvider, address(this));
        require(provision.createdAt != 0, ProvisionManagerProvisionNotFound(_serviceProvider));
        return provision;
    }

    /**
     * @notice Checks if a value is within a valid range.
     * @param _value The value to check.
     * @param _min The minimum allowed value.
     * @param _max The maximum allowed value.
     * @param _revertMessage The revert message to display if the value is out of range.
     */
    function _checkValueInRange(uint256 _value, uint256 _min, uint256 _max, bytes memory _revertMessage) private pure {
        require(_value.isInRange(_min, _max), ProvisionManagerInvalidValue(_revertMessage, _value, _min, _max));
    }
}
