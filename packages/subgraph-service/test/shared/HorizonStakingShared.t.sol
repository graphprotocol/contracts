// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { IHorizonStakingTypes } from "@graphprotocol/horizon/contracts/interfaces/internal/IHorizonStakingTypes.sol";
import { IHorizonStakingExtension } from "@graphprotocol/horizon/contracts/interfaces/internal/IHorizonStakingExtension.sol";

import { SubgraphBaseTest } from "../SubgraphBaseTest.t.sol";

abstract contract HorizonStakingSharedTest is SubgraphBaseTest {
    /*
     * HELPERS
     */

    function _createProvision(
        address _indexer,
        uint256 _tokens,
        uint32 _maxSlashingPercentage,
        uint64 _disputePeriod
    ) internal {
        _stakeTo(_indexer, _tokens);
        staking.provision(_indexer, address(subgraphService), _tokens, _maxSlashingPercentage, _disputePeriod);
    }

    function _addToProvision(address _indexer, uint256 _tokens) internal {
        _stakeTo(_indexer, _tokens);
        staking.addToProvision(_indexer, address(subgraphService), _tokens);
    }

    function _delegate(address _indexer, address _verifier, uint256 _tokens, uint256 _minSharesOut) internal {
        staking.delegate(_indexer, _verifier, _tokens, _minSharesOut);
    }

    function _setDelegationFeeCut(
        address _indexer,
        address _verifier,
        IGraphPayments.PaymentTypes _paymentType,
        uint256 _cut
    ) internal {
        staking.setDelegationFeeCut(_indexer, _verifier, _paymentType, _cut);
    }

    function _thawDeprovisionAndUnstake(address _indexer, address _verifier, uint256 _tokens) internal {
        // Initiate thaw request
        staking.thaw(_indexer, _verifier, _tokens);

        // Skip thawing period
        IHorizonStakingTypes.Provision memory provision = staking.getProvision(_indexer, _verifier);
        skip(provision.thawingPeriod + 1);

        // Deprovision and unstake
        staking.deprovision(_indexer, _verifier, 0);
        staking.unstake(_tokens);
    }

    function _setProvisionParameters(
        address _indexer,
        address _verifier,
        uint32 _maxVerifierCut,
        uint64 _thawingPeriod
    ) internal {
        staking.setProvisionParameters(_indexer, _verifier, _maxVerifierCut, _thawingPeriod);
    }

    function _setStorage_allocation_hardcoded(address indexer, address allocationId, uint256 tokens) internal {
        IHorizonStakingExtension.Allocation memory allocation = IHorizonStakingExtension.Allocation({
            indexer: indexer,
            subgraphDeploymentID: bytes32("0x12344321"),
            tokens: tokens,
            createdAtEpoch: 1234,
            closedAtEpoch: 1235,
            collectedFees: 1234,
            __DEPRECATED_effectiveAllocation: 1222234,
            accRewardsPerAllocatedToken: 1233334,
            distributedRebates: 1244434
        });

        // __DEPRECATED_allocations
        uint256 allocationsSlot = 15;
        bytes32 allocationBaseSlot = keccak256(abi.encode(allocationId, allocationsSlot));
        vm.store(address(staking), allocationBaseSlot, bytes32(uint256(uint160(allocation.indexer))));
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 1), allocation.subgraphDeploymentID);
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 2), bytes32(tokens));
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 3), bytes32(allocation.createdAtEpoch));
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 4), bytes32(allocation.closedAtEpoch));
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 5), bytes32(allocation.collectedFees));
        vm.store(
            address(staking),
            bytes32(uint256(allocationBaseSlot) + 6),
            bytes32(allocation.__DEPRECATED_effectiveAllocation)
        );
        vm.store(
            address(staking),
            bytes32(uint256(allocationBaseSlot) + 7),
            bytes32(allocation.accRewardsPerAllocatedToken)
        );
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 8), bytes32(allocation.distributedRebates));

        // _serviceProviders
        uint256 serviceProviderSlot = 14;
        bytes32 serviceProviderBaseSlot = keccak256(abi.encode(allocation.indexer, serviceProviderSlot));
        uint256 currentTokensStaked = uint256(vm.load(address(staking), serviceProviderBaseSlot));
        uint256 currentTokensProvisioned = uint256(
            vm.load(address(staking), bytes32(uint256(serviceProviderBaseSlot) + 1))
        );
        vm.store(
            address(staking),
            bytes32(uint256(serviceProviderBaseSlot) + 0),
            bytes32(currentTokensStaked + tokens)
        );
        vm.store(
            address(staking),
            bytes32(uint256(serviceProviderBaseSlot) + 1),
            bytes32(currentTokensProvisioned + tokens)
        );

        // __DEPRECATED_subgraphAllocations
        uint256 subgraphsAllocationsSlot = 16;
        bytes32 subgraphAllocationsBaseSlot = keccak256(
            abi.encode(allocation.subgraphDeploymentID, subgraphsAllocationsSlot)
        );
        uint256 currentAllocatedTokens = uint256(vm.load(address(staking), subgraphAllocationsBaseSlot));
        vm.store(address(staking), subgraphAllocationsBaseSlot, bytes32(currentAllocatedTokens + tokens));
    }

    /*
     * PRIVATE
     */

    function _stakeTo(address _indexer, uint256 _tokens) private {
        token.approve(address(staking), _tokens);
        staking.stakeTo(_indexer, _tokens);
    }
}
