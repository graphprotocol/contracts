// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.6 || ^0.8.0;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events

/**
 * @title IGraphTokenLockWallet
 * @author Edge & Node
 * @notice Interface for the GraphTokenLockWallet contract that manages locked tokens with vesting schedules
 * @dev This interface includes core vesting functionality. Protocol interaction functions are in IGraphTokenLockWalletToolshed
 */
interface IGraphTokenLockWallet {
    /**
     * @notice Revocability status for a vesting contract
     */
    enum Revocability {
        NotSet,
        Enabled,
        Disabled
    }

    // Events

    /// @notice Emitted when the manager is updated
    /// @param _oldManager The previous manager address
    /// @param _newManager The new manager address
    event ManagerUpdated(address indexed _oldManager, address indexed _newManager);

    /// @notice Emitted when ownership is transferred
    /// @param previousOwner The previous owner address
    /// @param newOwner The new owner address
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when token destinations are approved
    event TokenDestinationsApproved();

    /// @notice Emitted when token destinations are revoked
    event TokenDestinationsRevoked();

    /// @notice Emitted when tokens are released to beneficiary
    /// @param beneficiary The beneficiary address
    /// @param amount The amount of tokens released
    event TokensReleased(address indexed beneficiary, uint256 amount);

    /// @notice Emitted when tokens are revoked
    /// @param beneficiary The beneficiary address
    /// @param amount The amount of tokens revoked
    event TokensRevoked(address indexed beneficiary, uint256 amount);

    /// @notice Emitted when tokens are withdrawn
    /// @param beneficiary The beneficiary address
    /// @param amount The amount of tokens withdrawn
    event TokensWithdrawn(address indexed beneficiary, uint256 amount);

    // View functions - Vesting Details

    /// @notice Get the beneficiary address
    /// @return The beneficiary address
    function beneficiary() external view returns (address);

    /// @notice Get the token contract address
    /// @return The token contract address
    function token() external view returns (address);

    /// @notice Get the total amount of tokens managed by this contract
    /// @return The managed token amount
    function managedAmount() external view returns (uint256);

    /// @notice Get the vesting start time
    /// @return The start time timestamp
    function startTime() external view returns (uint256);

    /// @notice Get the vesting end time
    /// @return The end time timestamp
    function endTime() external view returns (uint256);

    /// @notice Get the number of vesting periods
    /// @return The number of periods
    function periods() external view returns (uint256);

    /// @notice Get the release start time
    /// @return The release start time timestamp
    function releaseStartTime() external view returns (uint256);

    /// @notice Get the vesting cliff time
    /// @return The cliff time timestamp
    function vestingCliffTime() external view returns (uint256);

    /// @notice Get the revocability status
    /// @return The revocability status
    function revocable() external view returns (Revocability);

    /// @notice Check if the vesting has been revoked
    /// @return True if revoked, false otherwise
    function isRevoked() external view returns (bool);

    // View functions - Vesting Calculations

    /// @notice Get the current timestamp
    /// @return The current timestamp
    function currentTime() external view returns (uint256);

    /// @notice Get the total vesting duration
    /// @return The duration in seconds
    function duration() external view returns (uint256);

    /// @notice Get the time elapsed since vesting start
    /// @return The elapsed time in seconds
    function sinceStartTime() external view returns (uint256);

    /// @notice Get the amount of tokens released per period
    /// @return The amount per period
    function amountPerPeriod() external view returns (uint256);

    /// @notice Get the duration of each vesting period
    /// @return The period duration in seconds
    function periodDuration() external view returns (uint256);

    /// @notice Get the current vesting period
    /// @return The current period number
    function currentPeriod() external view returns (uint256);

    /// @notice Get the number of periods that have passed
    /// @return The number of passed periods
    function passedPeriods() external view returns (uint256);

    // View functions - Token Amounts

    /// @notice Get the amount of tokens that can be released
    /// @return The releasable token amount
    function releasableAmount() external view returns (uint256);

    /// @notice Get the amount of tokens that have vested
    /// @return The vested token amount
    function vestedAmount() external view returns (uint256);

    /// @notice Get the amount of tokens that have been released
    /// @return The released token amount
    function releasedAmount() external view returns (uint256);

    /// @notice Get the amount of tokens that have been used
    /// @return The used token amount
    function usedAmount() external view returns (uint256);

    /// @notice Get the current token balance of the contract
    /// @return The current balance
    function currentBalance() external view returns (uint256);

    /// @notice Get the surplus amount of tokens
    /// @return The surplus token amount
    function surplusAmount() external view returns (uint256);

    /// @notice Get the total outstanding token amount
    /// @return The total outstanding amount
    function totalOutstandingAmount() external view returns (uint256);

    // State-changing functions

    /// @notice Release vested tokens to the beneficiary
    function release() external;

    /// @notice Withdraw surplus tokens
    /// @param _amount The amount of surplus tokens to withdraw
    function withdrawSurplus(uint256 _amount) external;

    /// @notice Approve protocol interactions
    function approveProtocol() external;

    /// @notice Revoke protocol interactions
    function revokeProtocol() external;

    // Fallback for forwarding calls

    /// @notice Fallback function for forwarding calls
    fallback() external payable;
}
