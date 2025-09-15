// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;
pragma abicoder v2;

import { IStakingData } from "./IStakingData.sol";
import { IStakes } from "./libs/IStakes.sol";

/**
 * @title Interface for the StakingExtension contract
 * @dev This interface defines the events and functions implemented
 * in the StakingExtension contract, which is used to extend the functionality
 * of the Staking contract while keeping it within the 24kB mainnet size limit.
 * In particular, this interface includes delegation functions and various storage
 * getters.
 */
interface IStakingExtension is IStakingData {
    /**
     * @dev DelegationPool struct as returned by delegationPools(), since
     * the original DelegationPool in IStakingData.sol contains a nested mapping.
     */
    struct DelegationPoolReturn {
        uint32 __DEPRECATED_cooldownBlocks; // solhint-disable-line var-name-mixedcase
        uint32 indexingRewardCut; // in PPM
        uint32 queryFeeCut; // in PPM
        uint256 updatedAtBlock; // Block when the pool was last updated
        uint256 tokens; // Total tokens as pool reserves
        uint256 shares; // Total shares minted in the pool
    }

    /**
     * @dev Emitted when `delegator` delegated `tokens` to the `indexer`, the delegator
     * gets `shares` for the delegation pool proportionally to the tokens staked.
     */
    event StakeDelegated(address indexed indexer, address indexed delegator, uint256 tokens, uint256 shares);

    /**
     * @dev Emitted when `delegator` undelegated `tokens` from `indexer`.
     * Tokens get locked for withdrawal after a period of time.
     */
    event StakeDelegatedLocked(
        address indexed indexer,
        address indexed delegator,
        uint256 tokens,
        uint256 shares,
        uint256 until
    );

    /**
     * @dev Emitted when `delegator` withdrew delegated `tokens` from `indexer`.
     */
    event StakeDelegatedWithdrawn(address indexed indexer, address indexed delegator, uint256 tokens);

    /**
     * @dev Emitted when `indexer` was slashed for a total of `tokens` amount.
     * Tracks `reward` amount of tokens given to `beneficiary`.
     */
    event StakeSlashed(address indexed indexer, uint256 tokens, uint256 reward, address beneficiary);

    /**
     * @dev Emitted when `caller` set `slasher` address as `allowed` to slash stakes.
     */
    event SlasherUpdate(address indexed caller, address indexed slasher, bool allowed);

    /**
     * @notice Set the delegation ratio.
     * If set to 10 it means the indexer can use up to 10x the indexer staked amount
     * from their delegated tokens
     * @dev This function is only callable by the governor
     * @param delegationRatio Delegation capacity multiplier
     */
    function setDelegationRatio(uint32 delegationRatio) external;

    /**
     * @notice Set the time, in epochs, a Delegator needs to wait to withdraw tokens after undelegating.
     * @dev This function is only callable by the governor
     * @param delegationUnbondingPeriod Period in epochs to wait for token withdrawals after undelegating
     */
    function setDelegationUnbondingPeriod(uint32 delegationUnbondingPeriod) external;

    /**
     * @notice Set a delegation tax percentage to burn when delegated funds are deposited.
     * @dev This function is only callable by the governor
     * @param percentage Percentage of delegated tokens to burn as delegation tax, expressed in parts per million
     */
    function setDelegationTaxPercentage(uint32 percentage) external;

    /**
     * @notice Set or unset an address as allowed slasher.
     * @dev This function can only be called by the governor.
     * @param slasher Address of the party allowed to slash indexers
     * @param allowed True if slasher is allowed
     */
    function setSlasher(address slasher, bool allowed) external;

    /**
     * @notice Delegate tokens to an indexer.
     * @param indexer Address of the indexer to which tokens are delegated
     * @param tokens Amount of tokens to delegate
     * @return Amount of shares issued from the delegation pool
     */
    function delegate(address indexer, uint256 tokens) external returns (uint256);

    /**
     * @notice Undelegate tokens from an indexer. Tokens will be locked for the unbonding period.
     * @param indexer Address of the indexer to which tokens had been delegated
     * @param shares Amount of shares to return and undelegate tokens
     * @return Amount of tokens returned for the shares of the delegation pool
     */
    function undelegate(address indexer, uint256 shares) external returns (uint256);

    /**
     * @notice Withdraw undelegated tokens once the unbonding period has passed, and optionally
     * re-delegate to a new indexer.
     * @param indexer Withdraw available tokens delegated to indexer
     * @param newIndexer Re-delegate to indexer address if non-zero, withdraw if zero address
     */
    function withdrawDelegated(address indexer, address newIndexer) external returns (uint256);

    /**
     * @notice Slash the indexer stake. Delegated tokens are not subject to slashing.
     * @dev Can only be called by the slasher role.
     * @param indexer Address of indexer to slash
     * @param tokens Amount of tokens to slash from the indexer stake
     * @param reward Amount of reward tokens to send to a beneficiary
     * @param beneficiary Address of a beneficiary to receive a reward for the slashing
     */
    function slash(address indexer, uint256 tokens, uint256 reward, address beneficiary) external;

    /**
     * @notice Return the delegation from a delegator to an indexer.
     * @param indexer Address of the indexer where funds have been delegated
     * @param delegator Address of the delegator
     * @return Delegation data
     */
    function getDelegation(address indexer, address delegator) external view returns (Delegation memory);

    /**
     * @notice Return whether the delegator has delegated to the indexer.
     * @param indexer Address of the indexer where funds have been delegated
     * @param delegator Address of the delegator
     * @return True if delegator has tokens delegated to the indexer
     */
    function isDelegator(address indexer, address delegator) external view returns (bool);

    /**
     * @notice Returns amount of delegated tokens ready to be withdrawn after unbonding period.
     * @param delegation Delegation of tokens from delegator to indexer
     * @return Amount of tokens to withdraw
     */
    function getWithdraweableDelegatedTokens(Delegation memory delegation) external view returns (uint256);

    /**
     * @notice Getter for the delegationRatio, i.e. the delegation capacity multiplier:
     * If delegation ratio is 100, and an Indexer has staked 5 GRT,
     * then they can use up to 500 GRT from the delegated stake
     * @return Delegation ratio
     */
    function delegationRatio() external view returns (uint32);

    /**
     * @notice Getter for delegationUnbondingPeriod:
     * Time in epochs a delegator needs to wait to withdraw delegated stake
     * @return Delegation unbonding period in epochs
     */
    function delegationUnbondingPeriod() external view returns (uint32);

    /**
     * @notice Getter for delegationTaxPercentage:
     * Percentage of tokens to tax a delegation deposit, expressed in parts per million
     * @return Delegation tax percentage in parts per million
     */
    function delegationTaxPercentage() external view returns (uint32);

    /**
     * @notice Getter for delegationPools[_indexer]:
     * gets the delegation pool structure for a particular indexer.
     * @param indexer Address of the indexer for which to query the delegation pool
     * @return Delegation pool as a DelegationPoolReturn struct
     */
    function delegationPools(address indexer) external view returns (DelegationPoolReturn memory);

    /**
     * @notice Getter for operatorAuth[_indexer][_maybeOperator]:
     * returns true if the operator is authorized to operate on behalf of the indexer.
     * @param indexer The indexer address for which to query authorization
     * @param maybeOperator The address that may or may not be an operator
     * @return True if the operator is authorized to operate on behalf of the indexer
     */
    function operatorAuth(address indexer, address maybeOperator) external view returns (bool);

    /**
     * @notice Getter for rewardsDestination[_indexer]:
     * returns the address where the indexer's rewards are sent.
     * @param indexer The indexer address for which to query the rewards destination
     * @return The address where the indexer's rewards are sent, zero if none is set in which case rewards are re-staked
     */
    function rewardsDestination(address indexer) external view returns (address);

    /**
     * @notice Getter for subgraphAllocations[_subgraphDeploymentId]:
     * returns the amount of tokens allocated to a subgraph deployment.
     * @param subgraphDeploymentId The subgraph deployment for which to query the allocations
     * @return The amount of tokens allocated to the subgraph deployment
     */
    function subgraphAllocations(bytes32 subgraphDeploymentId) external view returns (uint256);

    /**
     * @notice Getter for slashers[_maybeSlasher]:
     * returns true if the address is a slasher, i.e. an entity that can slash indexers
     * @param maybeSlasher Address for which to check the slasher role
     * @return True if the address is a slasher
     */
    function slashers(address maybeSlasher) external view returns (bool);

    /**
     * @notice Getter for minimumIndexerStake: the minimum
     * amount of GRT that an indexer needs to stake.
     * @return Minimum indexer stake in GRT
     */
    function minimumIndexerStake() external view returns (uint256);

    /**
     * @notice Getter for thawingPeriod: the time in blocks an
     * indexer needs to wait to unstake tokens.
     * @return Thawing period in blocks
     */
    function thawingPeriod() external view returns (uint32);

    /**
     * @notice Getter for curationPercentage: the percentage of
     * query fees that are distributed to curators.
     * @return Curation percentage in parts per million
     */
    function curationPercentage() external view returns (uint32);

    /**
     * @notice Getter for protocolPercentage: the percentage of
     * query fees that are burned as protocol fees.
     * @return Protocol percentage in parts per million
     */
    function protocolPercentage() external view returns (uint32);

    /**
     * @notice Getter for maxAllocationEpochs: the maximum time in epochs
     * that an allocation can be open before anyone is allowed to close it. This
     * also caps the effective allocation when sending the allocation's query fees
     * to the rebate pool.
     * @return Maximum allocation period in epochs
     */
    function maxAllocationEpochs() external view returns (uint32);

    /**
     * @notice Getter for the numerator of the rebates alpha parameter
     * @return Alpha numerator
     */
    function alphaNumerator() external view returns (uint32);

    /**
     * @notice Getter for the denominator of the rebates alpha parameter
     * @return Alpha denominator
     */
    function alphaDenominator() external view returns (uint32);

    /**
     * @notice Getter for the numerator of the rebates lambda parameter
     * @return Lambda numerator
     */
    function lambdaNumerator() external view returns (uint32);

    /**
     * @notice Getter for the denominator of the rebates lambda parameter
     * @return Lambda denominator
     */
    function lambdaDenominator() external view returns (uint32);

    /**
     * @notice Getter for stakes[_indexer]:
     * gets the stake information for an indexer as a IStakes.Indexer struct.
     * @param indexer Indexer address for which to query the stake information
     * @return Stake information for the specified indexer, as a IStakes.Indexer struct
     */
    function stakes(address indexer) external view returns (IStakes.Indexer memory);

    /**
     * @notice Getter for allocations[_allocationID]:
     * gets an allocation's information as an IStakingData.Allocation struct.
     * @param allocationID Allocation ID for which to query the allocation information
     * @return The specified allocation, as an IStakingData.Allocation struct
     */
    function allocations(address allocationID) external view returns (IStakingData.Allocation memory);
}
