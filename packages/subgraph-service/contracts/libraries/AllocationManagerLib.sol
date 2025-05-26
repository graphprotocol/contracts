// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IHorizonStaking } from "@graphprotocol/horizon/contracts/interfaces/IHorizonStaking.sol";
import { IRewardsManager } from "@graphprotocol/contracts/contracts/rewards/IRewardsManager.sol";
import { ProvisionTracker } from "@graphprotocol/horizon/contracts/data-service/libraries/ProvisionTracker.sol";

import { Allocation } from "../libraries/Allocation.sol";
import { LegacyAllocation } from "../libraries/LegacyAllocation.sol";
import { AllocationManager } from "../utilities/AllocationManager.sol";

library AllocationManagerLib {
    using ProvisionTracker for mapping(address => uint256);
    using Allocation for mapping(address => Allocation.State);
    using LegacyAllocation for mapping(address => LegacyAllocation.State);

    ///@dev EIP712 typehash for allocation id proof
    bytes32 private constant EIP712_ALLOCATION_ID_PROOF_TYPEHASH =
        keccak256("AllocationIdProof(address indexer,address allocationId)");

    struct AllocateParams {
        uint256 currentEpoch;
        IHorizonStaking graphStaking;
        IRewardsManager graphRewardsManager;
        bytes32 _encodeAllocationProof;
        address _indexer;
        address _allocationId;
        bytes32 _subgraphDeploymentId;
        uint256 _tokens;
        bytes _allocationProof;
        uint32 _delegationRatio;
    }

    /**
     * @notice Create an allocation
     * @dev The `_allocationProof` is a 65-bytes Ethereum signed message of `keccak256(indexerAddress,allocationId)`
     *
     * Requirements:
     * - `_allocationId` must not be the zero address
     *
     * Emits a {AllocationCreated} event
     *
     * @param _allocations The mapping of allocation ids to allocation states
     */
    function allocate(
        mapping(address allocationId => Allocation.State allocation) storage _allocations,
        mapping(address allocationId => LegacyAllocation.State allocation) storage _legacyAllocations,
        mapping(address indexer => uint256 tokens) storage allocationProvisionTracker,
        mapping(bytes32 subgraphDeploymentId => uint256 tokens) storage _subgraphAllocatedTokens,
        AllocateParams memory params
    ) external {
        require(params._allocationId != address(0), AllocationManager.AllocationManagerInvalidZeroAllocationId());

        _verifyAllocationProof(params._encodeAllocationProof, params._allocationId, params._allocationProof);

        // Ensure allocation id is not reused
        // need to check both subgraph service (on allocations.create()) and legacy allocations
        _legacyAllocations.revertIfExists(params.graphStaking, params._allocationId);

        Allocation.State memory allocation = _allocations.create(
            params._indexer,
            params._allocationId,
            params._subgraphDeploymentId,
            params._tokens,
            params.graphRewardsManager.onSubgraphAllocationUpdate(params._subgraphDeploymentId),
            params.currentEpoch
        );

        // Check that the indexer has enough tokens available
        // Note that the delegation ratio ensures overdelegation cannot be used
        allocationProvisionTracker.lock(params.graphStaking, params._indexer, params._tokens, params._delegationRatio);

        // Update total allocated tokens for the subgraph deployment
        _subgraphAllocatedTokens[allocation.subgraphDeploymentId] =
            _subgraphAllocatedTokens[allocation.subgraphDeploymentId] +
            allocation.tokens;

        emit AllocationManager.AllocationCreated(
            params._indexer,
            params._allocationId,
            params._subgraphDeploymentId,
            allocation.tokens,
            params.currentEpoch
        );
    }

    /**
     * @notice Verifies ownership of an allocation id by verifying an EIP712 allocation proof
     * @dev Requirements:
     * - Signer must be the allocation id address
     * @param _allocationId The id of the allocation
     * @param _proof The EIP712 proof, an EIP712 signed message of (indexer,allocationId)
     */
    function _verifyAllocationProof(
        bytes32 _encodeAllocationProof,
        address _allocationId,
        bytes memory _proof
    ) private pure {
        address signer = ECDSA.recover(_encodeAllocationProof, _proof);
        require(
            signer == _allocationId,
            AllocationManager.AllocationManagerInvalidAllocationProof(signer, _allocationId)
        );
    }
}
