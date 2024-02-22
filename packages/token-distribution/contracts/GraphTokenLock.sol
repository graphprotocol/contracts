// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import { Ownable as OwnableInitializable } from "./Ownable.sol";
import "./MathUtils.sol";
import "./IGraphTokenLock.sol";

/**
 * @title GraphTokenLock
 * @notice Contract that manages an unlocking schedule of tokens.
 * @dev The contract lock manage a number of tokens deposited into the contract to ensure that
 * they can only be released under certain time conditions.
 *
 * This contract implements a release scheduled based on periods and tokens are released in steps
 * after each period ends. It can be configured with one period in which case it is like a plain TimeLock.
 * It also supports revocation to be used for vesting schedules.
 *
 * The contract supports receiving extra funds than the managed tokens ones that can be
 * withdrawn by the beneficiary at any time.
 *
 * A releaseStartTime parameter is included to override the default release schedule and
 * perform the first release on the configured time. After that it will continue with the
 * default schedule.
 */
abstract contract GraphTokenLock is OwnableInitializable, IGraphTokenLock {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant MIN_PERIOD = 1;

    // -- State --

    IERC20 public token;
    address public beneficiary;

    // Configuration

    // Amount of tokens managed by the contract schedule
    uint256 public managedAmount;

    uint256 public startTime; // Start datetime (in unixtimestamp)
    uint256 public endTime; // Datetime after all funds are fully vested/unlocked (in unixtimestamp)
    uint256 public periods; // Number of vesting/release periods

    // First release date for tokens (in unixtimestamp)
    // If set, no tokens will be released before releaseStartTime ignoring
    // the amount to release each period
    uint256 public releaseStartTime;
    // A cliff set a date to which a beneficiary needs to get to vest
    // all preceding periods
    uint256 public vestingCliffTime;
    Revocability public revocable; // Whether to use vesting for locked funds

    // State

    bool public isRevoked;
    bool public isInitialized;
    bool public isAccepted;
    uint256 public releasedAmount;
    uint256 public revokedAmount;

    // -- Events --

    event TokensReleased(address indexed beneficiary, uint256 amount);
    event TokensWithdrawn(address indexed beneficiary, uint256 amount);
    event TokensRevoked(address indexed beneficiary, uint256 amount);
    event BeneficiaryChanged(address newBeneficiary);
    event LockAccepted();
    event LockCanceled();

    /**
     * @dev Only allow calls from the beneficiary of the contract
     */
    modifier onlyBeneficiary() {
        require(msg.sender == beneficiary, "!auth");
        _;
    }

    /**
     * @notice Initializes the contract
     * @param _owner Address of the contract owner
     * @param _beneficiary Address of the beneficiary of locked tokens
     * @param _managedAmount Amount of tokens to be managed by the lock contract
     * @param _startTime Start time of the release schedule
     * @param _endTime End time of the release schedule
     * @param _periods Number of periods between start time and end time
     * @param _releaseStartTime Override time for when the releases start
     * @param _vestingCliffTime Override time for when the vesting start
     * @param _revocable Whether the contract is revocable
     */
    function _initialize(
        address _owner,
        address _beneficiary,
        address _token,
        uint256 _managedAmount,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _periods,
        uint256 _releaseStartTime,
        uint256 _vestingCliffTime,
        Revocability _revocable
    ) internal {
        require(!isInitialized, "Already initialized");
        require(_owner != address(0), "Owner cannot be zero");
        require(_beneficiary != address(0), "Beneficiary cannot be zero");
        require(_token != address(0), "Token cannot be zero");
        require(_managedAmount > 0, "Managed tokens cannot be zero");
        require(_startTime != 0, "Start time must be set");
        require(_startTime < _endTime, "Start time > end time");
        require(_periods >= MIN_PERIOD, "Periods cannot be below minimum");
        require(_revocable != Revocability.NotSet, "Must set a revocability option");
        require(_releaseStartTime < _endTime, "Release start time must be before end time");
        require(_vestingCliffTime < _endTime, "Cliff time must be before end time");

        isInitialized = true;

        OwnableInitializable._initialize(_owner);
        beneficiary = _beneficiary;
        token = IERC20(_token);

        managedAmount = _managedAmount;

        startTime = _startTime;
        endTime = _endTime;
        periods = _periods;

        // Optionals
        releaseStartTime = _releaseStartTime;
        vestingCliffTime = _vestingCliffTime;
        revocable = _revocable;
    }

    /**
     * @notice Change the beneficiary of funds managed by the contract
     * @dev Can only be called by the beneficiary
     * @param _newBeneficiary Address of the new beneficiary address
     */
    function changeBeneficiary(address _newBeneficiary) external onlyBeneficiary {
        require(_newBeneficiary != address(0), "Empty beneficiary");
        beneficiary = _newBeneficiary;
        emit BeneficiaryChanged(_newBeneficiary);
    }

    /**
     * @notice Beneficiary accepts the lock, the owner cannot retrieve back the tokens
     * @dev Can only be called by the beneficiary
     */
    function acceptLock() external onlyBeneficiary {
        isAccepted = true;
        emit LockAccepted();
    }

    /**
     * @notice Owner cancel the lock and return the balance in the contract
     * @dev Can only be called by the owner
     */
    function cancelLock() external onlyOwner {
        require(isAccepted == false, "Cannot cancel accepted contract");

        token.safeTransfer(owner(), currentBalance());

        emit LockCanceled();
    }

    // -- Balances --

    /**
     * @notice Returns the amount of tokens currently held by the contract
     * @return Tokens held in the contract
     */
    function currentBalance() public view override returns (uint256) {
        return token.balanceOf(address(this));
    }

    // -- Time & Periods --

    /**
     * @notice Returns the current block timestamp
     * @return Current block timestamp
     */
    function currentTime() public view override returns (uint256) {
        return block.timestamp;
    }

    /**
     * @notice Gets duration of contract from start to end in seconds
     * @return Amount of seconds from contract startTime to endTime
     */
    function duration() public view override returns (uint256) {
        return endTime.sub(startTime);
    }

    /**
     * @notice Gets time elapsed since the start of the contract
     * @dev Returns zero if called before conctract starTime
     * @return Seconds elapsed from contract startTime
     */
    function sinceStartTime() public view override returns (uint256) {
        uint256 current = currentTime();
        if (current <= startTime) {
            return 0;
        }
        return current.sub(startTime);
    }

    /**
     * @notice Returns amount available to be released after each period according to schedule
     * @return Amount of tokens available after each period
     */
    function amountPerPeriod() public view override returns (uint256) {
        return managedAmount.div(periods);
    }

    /**
     * @notice Returns the duration of each period in seconds
     * @return Duration of each period in seconds
     */
    function periodDuration() public view override returns (uint256) {
        return duration().div(periods);
    }

    /**
     * @notice Gets the current period based on the schedule
     * @return A number that represents the current period
     */
    function currentPeriod() public view override returns (uint256) {
        return sinceStartTime().div(periodDuration()).add(MIN_PERIOD);
    }

    /**
     * @notice Gets the number of periods that passed since the first period
     * @return A number of periods that passed since the schedule started
     */
    function passedPeriods() public view override returns (uint256) {
        return currentPeriod().sub(MIN_PERIOD);
    }

    // -- Locking & Release Schedule --

    /**
     * @notice Gets the currently available token according to the schedule
     * @dev Implements the step-by-step schedule based on periods for available tokens
     * @return Amount of tokens available according to the schedule
     */
    function availableAmount() public view override returns (uint256) {
        uint256 current = currentTime();

        // Before contract start no funds are available
        if (current < startTime) {
            return 0;
        }

        // After contract ended all funds are available
        if (current > endTime) {
            return managedAmount;
        }

        // Get available amount based on period
        return passedPeriods().mul(amountPerPeriod());
    }

    /**
     * @notice Gets the amount of currently vested tokens
     * @dev Similar to available amount, but is fully vested when contract is non-revocable
     * @return Amount of tokens already vested
     */
    function vestedAmount() public view override returns (uint256) {
        // If non-revocable it is fully vested
        if (revocable == Revocability.Disabled) {
            return managedAmount;
        }

        // Vesting cliff is activated and it has not passed means nothing is vested yet
        if (vestingCliffTime > 0 && currentTime() < vestingCliffTime) {
            return 0;
        }

        return availableAmount();
    }

    /**
     * @notice Gets tokens currently available for release
     * @dev Considers the schedule and takes into account already released tokens
     * @return Amount of tokens ready to be released
     */
    function releasableAmount() public view virtual override returns (uint256) {
        // If a release start time is set no tokens are available for release before this date
        // If not set it follows the default schedule and tokens are available on
        // the first period passed
        if (releaseStartTime > 0 && currentTime() < releaseStartTime) {
            return 0;
        }

        // Vesting cliff is activated and it has not passed means nothing is vested yet
        // so funds cannot be released
        if (revocable == Revocability.Enabled && vestingCliffTime > 0 && currentTime() < vestingCliffTime) {
            return 0;
        }

        // A beneficiary can never have more releasable tokens than the contract balance
        uint256 releasable = availableAmount().sub(releasedAmount);
        return MathUtils.min(currentBalance(), releasable);
    }

    /**
     * @notice Gets the outstanding amount yet to be released based on the whole contract lifetime
     * @dev Does not consider schedule but just global amounts tracked
     * @return Amount of outstanding tokens for the lifetime of the contract
     */
    function totalOutstandingAmount() public view override returns (uint256) {
        return managedAmount.sub(releasedAmount).sub(revokedAmount);
    }

    /**
     * @notice Gets surplus amount in the contract based on outstanding amount to release
     * @dev All funds over outstanding amount is considered surplus that can be withdrawn by beneficiary.
     * Note this might not be the correct value for wallets transferred to L2 (i.e. an L2GraphTokenLockWallet), as the released amount will be
     * skewed, so the beneficiary might have to bridge back to L1 to release the surplus.
     * @return Amount of tokens considered as surplus
     */
    function surplusAmount() public view override returns (uint256) {
        uint256 balance = currentBalance();
        uint256 outstandingAmount = totalOutstandingAmount();
        if (balance > outstandingAmount) {
            return balance.sub(outstandingAmount);
        }
        return 0;
    }

    // -- Value Transfer --

    /**
     * @notice Releases tokens based on the configured schedule
     * @dev All available releasable tokens are transferred to beneficiary
     */
    function release() external override onlyBeneficiary {
        uint256 amountToRelease = releasableAmount();
        require(amountToRelease > 0, "No available releasable amount");

        releasedAmount = releasedAmount.add(amountToRelease);

        token.safeTransfer(beneficiary, amountToRelease);

        emit TokensReleased(beneficiary, amountToRelease);
    }

    /**
     * @notice Withdraws surplus, unmanaged tokens from the contract
     * @dev Tokens in the contract over outstanding amount are considered as surplus
     * @param _amount Amount of tokens to withdraw
     */
    function withdrawSurplus(uint256 _amount) external override onlyBeneficiary {
        require(_amount > 0, "Amount cannot be zero");
        require(surplusAmount() >= _amount, "Amount requested > surplus available");

        token.safeTransfer(beneficiary, _amount);

        emit TokensWithdrawn(beneficiary, _amount);
    }

    /**
     * @notice Revokes a vesting schedule and return the unvested tokens to the owner
     * @dev Vesting schedule is always calculated based on managed tokens
     */
    function revoke() external override onlyOwner {
        require(revocable == Revocability.Enabled, "Contract is non-revocable");
        require(isRevoked == false, "Already revoked");

        uint256 unvestedAmount = managedAmount.sub(vestedAmount());
        require(unvestedAmount > 0, "No available unvested amount");

        revokedAmount = unvestedAmount;
        isRevoked = true;

        token.safeTransfer(owner(), unvestedAmount);

        emit TokensRevoked(beneficiary, unvestedAmount);
    }
}
