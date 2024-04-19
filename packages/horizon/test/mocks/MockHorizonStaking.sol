// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";

contract MockHorizonStaking is IHorizonStaking {
    uint256 public delegationCut;
    mapping(address serviceProvider => uint256 tokens) public delegationPool;

    constructor(uint256 _delegationCut) {
        delegationCut = _delegationCut;
    }

    function allowVerifier(address verifier, bool allow) external {}
    function stake(uint256 tokens) external {}
    function provision(uint256 tokens, address verifier, uint256 maxVerifierCut, uint256 thawingPeriod) external {}
    function thaw(bytes32 provisionId, uint256 tokens) external returns (bytes32 thawRequestId) {}
    function deprovision(bytes32 thawRequestId) external {}
    function reprovision(bytes32 thawRequestId, bytes32 provisionId) external {}
    function withdraw(bytes32 thawRequestId) external {}
    function delegate(address serviceProvider, uint256 tokens) external {}
    function undelegate(
        address serviceProvider,
        uint256 tokens,
        bytes32[] calldata provisions
    ) external returns (bytes32 thawRequestId) {}
    function slash(bytes32 provisionId, uint256 tokens, uint256 verifierAmount) external {}
    function setForceThawProvisions(bytes32[] calldata provisions) external {}
    function getStake(address serviceProvider) external view returns (uint256 tokens) {}
    function getIdleStake(address serviceProvider) external view returns (uint256 tokens) {}
    function getCapacity(address serviceProvider) external view returns (uint256 tokens) {}
    function getTokensAvailable(bytes32 provision) external view returns (uint256 tokens) {}
    function getServiceProvider(address serviceProvider) external view returns (ServiceProvider memory) {}
    function getProvision(bytes32 provision) external view returns (Provision memory) {}

    function getDelegationCut(address serviceProvider, uint8 paymentType) external view returns (uint256) {
        return delegationCut;
    }

    function addToDelegationPool(address serviceProvider, uint256 tokens) external {
        delegationPool[serviceProvider] += tokens;
    }
}