// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.6 || 0.8.27;

/**
 * @title IGraphTokenLockWallet
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
    event ManagerUpdated(address indexed _oldManager, address indexed _newManager);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TokenDestinationsApproved();
    event TokenDestinationsRevoked();
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event TokensRevoked(address indexed beneficiary, uint256 amount);
    event TokensWithdrawn(address indexed beneficiary, uint256 amount);

    // View functions - Vesting Details
    function beneficiary() external view returns (address);
    function token() external view returns (address);
    function managedAmount() external view returns (uint256);
    function startTime() external view returns (uint256);
    function endTime() external view returns (uint256);
    function periods() external view returns (uint256);
    function releaseStartTime() external view returns (uint256);
    function vestingCliffTime() external view returns (uint256);
    function revocable() external view returns (Revocability);
    function isRevoked() external view returns (bool);

    // View functions - Vesting Calculations
    function currentTime() external view returns (uint256);
    function duration() external view returns (uint256);
    function sinceStartTime() external view returns (uint256);
    function amountPerPeriod() external view returns (uint256);
    function periodDuration() external view returns (uint256);
    function currentPeriod() external view returns (uint256);
    function passedPeriods() external view returns (uint256);

    // View functions - Token Amounts
    function releasableAmount() external view returns (uint256);
    function vestedAmount() external view returns (uint256);
    function releasedAmount() external view returns (uint256);
    function usedAmount() external view returns (uint256);
    function currentBalance() external view returns (uint256);
    function surplusAmount() external view returns (uint256);
    function totalOutstandingAmount() external view returns (uint256);

    // State-changing functions
    function release() external;
    function withdrawSurplus(uint256 _amount) external;
    function approveProtocol() external;
    function revokeProtocol() external;

    // Fallback for forwarding calls
    fallback() external payable;
}
