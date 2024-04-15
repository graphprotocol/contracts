// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";
import { GraphDirectory } from "./GraphDirectory.sol";

import { DataServiceV1Storage } from "./DataServiceStorage.sol";
import { IDataService } from "./IDataService.sol";

abstract contract DataService is GraphDirectory, DataServiceV1Storage, IDataService {
    error GraphDataServiceNotAuthorized(address caller, address serviceProvider, address service);
    error GraphDataServiceProvisionNotFound(address serviceProvider, address service);
    error GraphDataServiceInvalidProvisionTokens(
        uint256 tokens,
        uint256 minimumProvisionTokens,
        uint256 maximumProvisionTokens
    );
    error GraphDataServiceInvalidVerifierCut(
        uint256 verifierCut,
        uint256 minimumVerifierCut,
        uint256 maximumVerifierCut
    );
    error GraphDataServiceInvalidThawingPeriod(
        uint64 thawingPeriod,
        uint64 minimumThawingPeriod,
        uint64 maximumThawingPeriod
    );

    modifier onlyProvisionAuthorized(address serviceProvider) {
        if (!graphStaking.isAuthorized(msg.sender, serviceProvider, address(this))) {
            revert GraphDataServiceNotAuthorized(msg.sender, serviceProvider, address(this));
        }
        _;
    }

    constructor(address _controller) GraphDirectory(_controller) {
        minimumProvisionTokens = type(uint256).min;
        maximumProvisionTokens = type(uint256).max;

        minimumThawingPeriod = type(uint64).min;
        maximumThawingPeriod = type(uint64).max;

        minimumVerifierCut = type(uint32).min;
        maximumVerifierCut = type(uint32).max;
    }

    // solhint-disable-next-line no-unused-vars
    function acceptProvision(address indexer, bytes calldata _data) external onlyProvisionAuthorized(indexer) {
        _checkProvisionParameters(indexer);
        _acceptProvision(indexer);
    }

    function _slash(address serviceProvider, uint256 tokens, uint256 reward, address rewardsDestination) internal {
        graphStaking.slash(serviceProvider, tokens, reward, rewardsDestination);
    }

    function _getProvision(address serviceProvider) internal view returns (IHorizonStaking.Provision memory) {
        IHorizonStaking.Provision memory provision = graphStaking.getProvision(serviceProvider, address(this));
        if (provision.createdAt == 0) {
            revert GraphDataServiceProvisionNotFound(serviceProvider, address(this));
        }
        return provision;
    }

    /// @notice Checks if the service provider has a valid provision for the data service in the staking contract
    /// @param serviceProvider The address of the service provider
    function _checkProvisionParameters(address serviceProvider) internal view virtual {
        IHorizonStaking.Provision memory provision = _getProvision(serviceProvider);

        (uint256 provisionTokensMin, uint256 provisionTokensMax) = _getProvisionTokensRange();
        if (!_isInRange(provision.tokens, provisionTokensMin, provisionTokensMax)) {
            revert GraphDataServiceInvalidProvisionTokens(provision.tokens, provisionTokensMin, provisionTokensMax);
        }

        (uint64 thawingPeriodMin, uint64 thawingPeriodMax) = _getThawingPeriodRange();
        if (!_isInRange(provision.thawingPeriod, thawingPeriodMin, thawingPeriodMax)) {
            revert GraphDataServiceInvalidThawingPeriod(provision.thawingPeriod, thawingPeriodMin, thawingPeriodMax);
        }

        (uint32 verifierCutMin, uint32 verifierCutMax) = _getVerifierCutRange();
        if (!_isInRange(provision.maxVerifierCut, verifierCutMin, verifierCutMax)) {
            revert GraphDataServiceInvalidVerifierCut(provision.maxVerifierCut, verifierCutMin, verifierCutMax);
        }
    }

    function _acceptProvision(address serviceProvider) internal virtual {
        graphStaking.acceptProvision(serviceProvider);
    }

    function _setProvisionTokensRange(uint256 min, uint256 max) internal {
        minimumProvisionTokens = min;
        maximumProvisionTokens = max;
    }

    function _setVerifierCutRange(uint32 min, uint32 max) internal {
        minimumVerifierCut = min;
        maximumVerifierCut = max;
    }

    function _setThawingPeriodRange(uint64 min, uint64 max) internal {
        minimumThawingPeriod = min;
        maximumThawingPeriod = max;
    }

    function _getProvisionTokensRange() internal view virtual returns (uint256 min, uint256 max) {
        return (minimumProvisionTokens, maximumProvisionTokens);
    }

    function _getThawingPeriodRange() internal view virtual returns (uint64 min, uint64 max) {
        return (minimumThawingPeriod, maximumThawingPeriod);
    }

    function _getVerifierCutRange() internal view virtual returns (uint32 min, uint32 max) {
        return (minimumVerifierCut, maximumVerifierCut);
    }

    function _isInRange(uint256 value, uint256 min, uint256 max) private pure returns (bool) {
        return value >= min && value <= max;
    }
}
