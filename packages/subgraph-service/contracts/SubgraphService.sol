// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";
import { ISubgraphService } from "./ISubgraphService.sol";
import { IDisputeManager } from "./IDisputeManager.sol";

import { SubgraphServiceV1Storage } from "./SubgraphServiceStorage.sol";

abstract contract SubgraphService is Ownable(msg.sender), SubgraphServiceV1Storage, ISubgraphService {
    error SubgraphServiceNotAuthorized(address caller, address serviceProvider, address service);
    error SubgraphServiceNotDisputeManager(address caller, address disputeManager);
    error SubgraphServiceAlreadyRegistered();
    error SubgraphServiceEmptyUrl();
    error SubgraphServiceProvisionNotFound(address serviceProvider, address service);
    error SubgraphServiceInvalidProvisionVerifierCut(uint256 verifierCut, uint256 maxVerifierCut);
    error SubgraphServiceInvalidProvisionTokens(uint256 tokens, uint256 minimumProvisionTokens);
    error SubgraphServiceInvalidProvisionThawingPeriod(uint64 thawingPeriod, uint64 disputePeriod);

    event StakingSet(address staking);
    event DisputeManagerSet(address disputeManager);
    event MinimumProvisionTokensSet(uint256 minimumProvisionTokens);

    modifier onlyAuthorized(address serviceProvider) {
        if (!staking.isAuthorized(msg.sender, serviceProvider, address(this))) {
            revert SubgraphServiceNotAuthorized(msg.sender, serviceProvider, address(this));
        }
        _;
    }

    modifier onlyDisputeManager() {
        if (msg.sender != address(disputeManager)) {
            revert SubgraphServiceNotDisputeManager(msg.sender, address(disputeManager));
        }
        _;
    }

    constructor(address _staking, address _disputeManager, uint256 _minimumProvisionTokens) {
        // TODO: some address validation here, not zero, etc
        staking = IHorizonStaking(_staking);
        emit StakingSet(_staking);

        _setDisputeManager(_disputeManager);
        _setMinimumProvisionTokens(_minimumProvisionTokens);
    }

    // TODO: implement provisionAndRegister convenience method
    function register(
        address serviceProvider,
        string calldata url,
        string calldata geohash
    ) external override onlyAuthorized(serviceProvider) {
        // Must provide a URL
        if (bytes(url).length == 0) {
            revert SubgraphServiceEmptyUrl();
        }

        // Only allow registering once
        if (indexers[serviceProvider].registeredAt != 0) {
            revert SubgraphServiceAlreadyRegistered();
        }

        // Ensure the service provider created a valid provision for the data service
        _checkProvision(serviceProvider);

        // TODO: save delegator cut parameters
        // Register the service provider
        indexers[serviceProvider] = Indexer(
            block.timestamp,
            url,
            geohash,
            0, // tokensUsed
            0 // tokensCollected
        );
    }

    function slash(address serviceProvider, uint256 tokens, uint256 reward) external override onlyDisputeManager {
        staking.slash(serviceProvider, tokens, reward, address(disputeManager));
    }

    function setDisputeManager(address _disputeManager) external onlyOwner {
        _setDisputeManager(_disputeManager);
    }

    function setMinimumProvisionTokens(uint256 _minimumProvisionTokens) external onlyOwner {
        _setMinimumProvisionTokens(_minimumProvisionTokens);
    }

    function _setDisputeManager(address _disputeManager) internal {
        disputeManager = IDisputeManager(_disputeManager);
        emit DisputeManagerSet(_disputeManager);
    }

    function _setMinimumProvisionTokens(uint256 _minimumProvisionTokens) internal {
        minimumProvisionTokens = _minimumProvisionTokens;
        emit MinimumProvisionTokensSet(minimumProvisionTokens);
    }

    function _register(address provisionId, string calldata url, string calldata geohash) internal {}

    function _getProvision(address serviceProvider) internal view returns (IHorizonStaking.Provision memory) {
        IHorizonStaking.Provision memory provision = staking.getProvision(serviceProvider, address(this));
        if (provision.createdAt == 0) {
            revert SubgraphServiceProvisionNotFound(serviceProvider, address(this));
        }
        return provision;
    }

    /// @notice Checks if the service provider has a valid provision for the data service in the staking contract
    /// @param serviceProvider The address of the service provider
    function _checkProvision(address serviceProvider) internal view {
        IHorizonStaking.Provision memory provision = _getProvision(serviceProvider);

        // Ensure the provision meets the data service requirements
        // ... it allows taking the verifier cut
        uint256 verifierCut = disputeManager.getVerifierCut();
        if (provision.maxVerifierCut >= verifierCut) {
            revert SubgraphServiceInvalidProvisionVerifierCut(verifierCut, provision.maxVerifierCut);
        }

        // ... it has enough stake
        if (provision.tokens < minimumProvisionTokens) {
            revert SubgraphServiceInvalidProvisionTokens(provision.tokens, minimumProvisionTokens);
        }

        // ... it allows enough time for dispute resolution before service provider can withdraw funds
        uint64 disputePeriod = disputeManager.getDisputePeriod();
        if (provision.thawingPeriod >= disputePeriod) {
            revert SubgraphServiceInvalidProvisionThawingPeriod(provision.thawingPeriod, disputePeriod);
        }
    }
}
