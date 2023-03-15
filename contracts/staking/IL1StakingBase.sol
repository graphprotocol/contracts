// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.6.12 <0.8.0;
pragma abicoder v2;

import { IL1GraphTokenLockMigrator } from "./IL1GraphTokenLockMigrator.sol";

/**
 * @title Base interface for the L1Staking contract.
 * @notice This interface is used to define the migration helpers that are implemented in L1Staking.
 * @dev Note it includes only the L1-specific functionality, not the full IStaking interface.
 */
interface IL1StakingBase {
    /// @dev Emitted when an indexer migrates their stake to L2.
    /// This can happen several times as indexers can migrate partial stake.
    event IndexerMigratedToL2(
        address indexed indexer,
        address indexed l2Indexer,
        uint256 migratedStakeTokens
    );

    /// @dev Emitted when a delegator migrates their delegation to L2
    event DelegationMigratedToL2(
        address indexed delegator,
        address indexed l2Delegator,
        address indexed indexer,
        address l2Indexer,
        uint256 migratedDelegationTokens
    );

    /// @dev Emitted when the L1GraphTokenLockMigrator is set
    event L1GraphTokenLockMigratorSet(address l1GraphTokenLockMigrator);

    /// @dev Emitted when a delegator unlocks their tokens ahead of time because the indexer has migrated
    event StakeDelegatedUnlockedDueToMigration(address indexed indexer, address indexed delegator);

    /**
     * @notice Set the L1GraphTokenLockMigrator contract address
     * @dev This function can only be called by the governor.
     * @param _l1GraphTokenLockMigrator Address of the L1GraphTokenLockMigrator contract
     */
    function setL1GraphTokenLockMigrator(IL1GraphTokenLockMigrator _l1GraphTokenLockMigrator)
        external;

    /**
     * @notice Send an indexer's stake to L2.
     * @dev This function can only be called by the indexer (not an operator).
     * It will validate that the remaining stake is sufficient to cover all the allocated
     * stake, so the indexer might have to close some allocations before migrating.
     * It will also check that the indexer's stake is not locked for withdrawal.
     * Since the indexer address might be an L1-only contract, the function takes a beneficiary
     * address that will be the indexer's address in L2.
     * The caller must provide an amount of ETH to use for the L2 retryable ticket, that
     * must be at least `_maxSubmissionCost + _gasPriceBid * _maxGas`.
     * @param _l2Beneficiary Address of the indexer in L2. If the indexer has previously migrated stake, this must match the previously-used value.
     * @param _amount Amount of stake GRT to migrate to L2
     * @param _maxGas Max gas to use for the L2 retryable ticket
     * @param _gasPriceBid Gas price bid for the L2 retryable ticket
     * @param _maxSubmissionCost Max submission cost for the L2 retryable ticket
     */
    function migrateStakeToL2(
        address _l2Beneficiary,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost
    ) external payable;

    /**
     * @notice Send an indexer's stake to L2, from a GraphTokenLockWallet vesting contract.
     * @dev This function can only be called by the indexer (not an operator).
     * It will validate that the remaining stake is sufficient to cover all the allocated
     * stake, so the indexer might have to close some allocations before migrating.
     * It will also check that the indexer's stake is not locked for withdrawal.
     * The L2 beneficiary for the stake will be determined by calling the L1GraphTokenLockMigrator contract,
     * so the caller must have previously migrated tokens through that first
     * (see GIP-0046 for details: https://forum.thegraph.com/t/gip-0046-l2-migration-helpers/4023).
     * The ETH for the L2 gas will be pulled from the L1GraphTokenLockMigrator, so the owner of
     * the GraphTokenLockWallet must have previously deposited at least `_maxSubmissionCost + _gasPriceBid * _maxGas`
     * ETH into the L1GraphTokenLockMigrator contract (using its depositETH function).
     * @param _amount Amount of stake GRT to migrate to L2
     * @param _maxGas Max gas to use for the L2 retryable ticket
     * @param _gasPriceBid Gas price bid for the L2 retryable ticket
     * @param _maxSubmissionCost Max submission cost for the L2 retryable ticket
     */
    function migrateLockedStakeToL2(
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost
    ) external;

    /**
     * @notice Send a delegator's delegated tokens to L2
     * @dev This function can only be called by the delegator.
     * This function will validate that the indexer has migrated their stake using migrateStakeToL2,
     * and that the delegation is not locked for undelegation.
     * Since the delegator's address might be an L1-only contract, the function takes a beneficiary
     * address that will be the delegator's address in L2.
     * The caller must provide an amount of ETH to use for the L2 retryable ticket, that
     * must be at least `_maxSubmissionCost + _gasPriceBid * _maxGas`.
     * @param _indexer Address of the indexer (in L1, before migrating)
     * @param _l2Beneficiary Address of the delegator in L2
     * @param _maxGas Max gas to use for the L2 retryable ticket
     * @param _gasPriceBid Gas price bid for the L2 retryable ticket
     * @param _maxSubmissionCost Max submission cost for the L2 retryable ticket
     */
    function migrateDelegationToL2(
        address _indexer,
        address _l2Beneficiary,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost
    ) external payable;

    /**
     * @notice Send a delegator's delegated tokens to L2, for a GraphTokenLockWallet vesting contract
     * @dev This function can only be called by the delegator.
     * This function will validate that the indexer has migrated their stake using migrateStakeToL2,
     * and that the delegation is not locked for undelegation.
     * The L2 beneficiary for the delegation will be determined by calling the L1GraphTokenLockMigrator contract,
     * so the caller must have previously migrated tokens through that first
     * (see GIP-0046 for details: https://forum.thegraph.com/t/gip-0046-l2-migration-helpers/4023).
     * The ETH for the L2 gas will be pulled from the L1GraphTokenLockMigrator, so the owner of
     * the GraphTokenLockWallet must have previously deposited at least `_maxSubmissionCost + _gasPriceBid * _maxGas`
     * ETH into the L1GraphTokenLockMigrator contract (using its depositETH function).
     * @param _indexer Address of the indexer (in L1, before migrating)
     * @param _maxGas Max gas to use for the L2 retryable ticket
     * @param _gasPriceBid Gas price bid for the L2 retryable ticket
     * @param _maxSubmissionCost Max submission cost for the L2 retryable ticket
     */
    function migrateLockedDelegationToL2(
        address _indexer,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost
    ) external;

    /**
     * @notice Unlock a delegator's delegated tokens, if the indexer has migrated
     * @dev This function can only be called by the delegator.
     * This function will validate that the indexer has migrated their stake using migrateStakeToL2,
     * and that the indexer has no remaining stake in L1.
     * The tokens must previously be locked for undelegation by calling `undelegate()`,
     * and can be withdrawn with `withdrawDelegated()` immediately after calling this.
     * @param _indexer Address of the indexer (in L1, before migrating)
     */
    function unlockDelegationToMigratedIndexer(address _indexer) external;
}
