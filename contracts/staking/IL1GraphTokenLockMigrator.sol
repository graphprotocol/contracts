// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.6.12 <0.8.0;
pragma abicoder v2;

/**
 * @title Interface for the L1GraphTokenLockMigrator contract
 * @dev This interface defines the function to get the migrated wallet address for a given L1 token lock wallet.
 * The migrator contract is implemented in the token-distribution repo: https://github.com/graphprotocol/token-distribution/pull/64
 * and is only included here to provide support in L1Staking for the migration of stake and delegation
 * owned by token lock contracts. See GIP-0046 for details: https://forum.thegraph.com/t/gip-0046-l2-migration-helpers/4023
 */
interface IL1GraphTokenLockMigrator {
    /**
     * @notice Pulls ETH from an L1 wallet's account to use for L2 ticket gas.
     * @dev This function is only callable by the staking contract.
     * @param _l1Wallet Address of the L1 token lock wallet
     * @param _amount Amount of ETH to pull from the migrator contract
     */
    function pullETH(address _l1Wallet, uint256 _amount) external;

    /**
     * @notice Get the L2 token lock wallet address for a given L1 token lock wallet
     * @dev In the actual L1GraphTokenLockMigrator contract, this is simply the default getter for a public mapping variable.
     * @param _l1Wallet Address of the L1 token lock wallet
     * @return Address of the L2 token lock wallet if the wallet has an L2 counterpart, or address zero if
     * the wallet doesn't have an L2 counterpart (or is not known to be a token lock wallet).
     */
    function migratedWalletAddress(address _l1Wallet) external view returns (address);
}
