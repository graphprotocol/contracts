// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IHorizonStaking } from "@graphprotocol/horizon/contracts/interfaces/IHorizonStaking.sol";
import { IHorizonStakingTypes } from "@graphprotocol/horizon/contracts/interfaces/IHorizonStakingTypes.sol";
import { MockGRTToken } from "./MockGRTToken.sol";

contract MockHorizonStaking {
    mapping (address verifier => mapping (address serviceProvider => IHorizonStaking.Provision provision)) public _provisions;
    MockGRTToken public grtToken;

    constructor(address _grtTokenAddress) {
        grtToken = MockGRTToken(_grtTokenAddress);
    }

    // whitelist/deny a verifier
    function allowVerifier(address verifier, bool allow) external {}

    // deposit stake
    function stake(uint256 tokens) external {}

    // create a provision
    function provision(uint256 tokens, address verifier, uint32 maxVerifierCut, uint64 thawingPeriod) external {
        IHorizonStaking.Provision memory newProvision = IHorizonStakingTypes.Provision({
            tokens: tokens,
            tokensThawing: 0,
            sharesThawing: 0,
            maxVerifierCut: maxVerifierCut,
            thawingPeriod: thawingPeriod,
            createdAt: uint64(block.timestamp),
            firstThawRequestId: bytes32(0),
            lastThawRequestId: bytes32(0),
            nThawRequests: 0,
            maxVerifierCutPending: maxVerifierCut,
            thawingPeriodPending: thawingPeriod
        });
        _provisions[verifier][msg.sender] = newProvision;
    }

    function acceptProvision(address serviceProvider) external {}

    // initiate a thawing to remove tokens from a provision
    function thaw(bytes32 provisionId, uint256 tokens) external returns (bytes32 thawRequestId) {}

    // moves thawed stake from a provision back into the provider's available stake
    function deprovision(bytes32 thawRequestId) external {}

    // moves thawed stake from one provision into another provision
    function reprovision(bytes32 thawRequestId, bytes32 provisionId) external {}

    // moves thawed stake back to the owner's account - stake is removed from the protocol
    function withdraw(bytes32 thawRequestId) external {}

    // delegate tokens to a provider
    function delegate(address serviceProvider, uint256 tokens) external {}

    // undelegate tokens
    function undelegate(
        address serviceProvider,
        uint256 tokens,
        bytes32[] calldata provisions
    ) external returns (bytes32 thawRequestId) {}

    // slash a service provider
    function slash(address serviceProvider, uint256 tokens, uint256 reward, address rewardsDestination) external {
        grtToken.mint(rewardsDestination, reward);
        grtToken.burnFrom(serviceProvider, tokens);
    }

    // set the Service Provider's preferred provisions to be force thawed
    function setForceThawProvisions(bytes32[] calldata provisions) external {}

    // total staked tokens to the provider
    // `ServiceProvider.tokensStaked + DelegationPool.serviceProvider.tokens`
    function getStake(address serviceProvider) external view returns (uint256 tokens) {}

    // staked tokens that are currently not provisioned, aka idle stake
    // `getStake(serviceProvider) - ServiceProvider.tokensProvisioned`
    function getIdleStake(address serviceProvider) external view returns (uint256 tokens) {}

    // staked tokens the provider can provision before hitting the delegation cap
    // `ServiceProvider.tokensStaked * Staking.delegationRatio - Provision.tokensProvisioned`
    function getCapacity(address serviceProvider) external view returns (uint256 tokens) {}

    // provisioned tokens that are not being used
    // `Provision.tokens - Provision.tokensThawing`
    function getTokensAvailable(address serviceProvider, address verifier) external view returns (uint256 tokens) {
        return _provisions[verifier][serviceProvider].tokens;
    }

    function getServiceProvider(address serviceProvider) external view returns (IHorizonStaking.ServiceProvider memory) {}

    function getProvision(address serviceProvider, address verifier) external view returns (IHorizonStaking.Provision memory) {
        return _provisions[verifier][serviceProvider];
    }

    function isAuthorized(address, address, address) external pure returns (bool) {
        return true;
    }

    function getDelegationCut(address serviceProvider, uint8 paymentType) external view returns (uint256 delegationCut) {}
    function addToDelegationPool(address serviceProvider, uint256 tokens) external {}
    function stakeToProvision(address _serviceProvider, address _verifier, uint256 _tokens) external {}
}