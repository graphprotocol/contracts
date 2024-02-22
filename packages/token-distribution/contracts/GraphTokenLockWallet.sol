// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./GraphTokenLock.sol";
import "./IGraphTokenLockManager.sol";

/**
 * @title GraphTokenLockWallet
 * @notice This contract is built on top of the base GraphTokenLock functionality.
 * It allows wallet beneficiaries to use the deposited funds to perform specific function calls
 * on specific contracts.
 *
 * The idea is that supporters with locked tokens can participate in the protocol
 * but disallow any release before the vesting/lock schedule.
 * The beneficiary can issue authorized function calls to this contract that will
 * get forwarded to a target contract. A target contract is any of our protocol contracts.
 * The function calls allowed are queried to the GraphTokenLockManager, this way
 * the same configuration can be shared for all the created lock wallet contracts.
 *
 * NOTE: Contracts used as target must have its function signatures checked to avoid collisions
 * with any of this contract functions.
 * Beneficiaries need to approve the use of the tokens to the protocol contracts. For convenience
 * the maximum amount of tokens is authorized.
 * Function calls do not forward ETH value so DO NOT SEND ETH TO THIS CONTRACT.
 */
contract GraphTokenLockWallet is GraphTokenLock {
    using SafeMath for uint256;

    // -- State --

    IGraphTokenLockManager public manager;
    uint256 public usedAmount;

    // -- Events --

    event ManagerUpdated(address indexed _oldManager, address indexed _newManager);
    event TokenDestinationsApproved();
    event TokenDestinationsRevoked();

    // Initializer
    function initialize(
        address _manager,
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
    ) external {
        _initialize(
            _owner,
            _beneficiary,
            _token,
            _managedAmount,
            _startTime,
            _endTime,
            _periods,
            _releaseStartTime,
            _vestingCliffTime,
            _revocable
        );
        _setManager(_manager);
    }

    // -- Admin --

    /**
     * @notice Sets a new manager for this contract
     * @param _newManager Address of the new manager
     */
    function setManager(address _newManager) external onlyOwner {
        _setManager(_newManager);
    }

    /**
     * @dev Sets a new manager for this contract
     * @param _newManager Address of the new manager
     */
    function _setManager(address _newManager) internal {
        require(_newManager != address(0), "Manager cannot be empty");
        require(Address.isContract(_newManager), "Manager must be a contract");

        address oldManager = address(manager);
        manager = IGraphTokenLockManager(_newManager);

        emit ManagerUpdated(oldManager, _newManager);
    }

    // -- Beneficiary --

    /**
     * @notice Approves protocol access of the tokens managed by this contract
     * @dev Approves all token destinations registered in the manager to pull tokens
     */
    function approveProtocol() external onlyBeneficiary {
        address[] memory dstList = manager.getTokenDestinations();
        for (uint256 i = 0; i < dstList.length; i++) {
            // Note this is only safe because we are using the max uint256 value
            token.approve(dstList[i], type(uint256).max);
        }
        emit TokenDestinationsApproved();
    }

    /**
     * @notice Revokes protocol access of the tokens managed by this contract
     * @dev Revokes approval to all token destinations in the manager to pull tokens
     */
    function revokeProtocol() external onlyBeneficiary {
        address[] memory dstList = manager.getTokenDestinations();
        for (uint256 i = 0; i < dstList.length; i++) {
            // Note this is only safe cause we're using 0 as the amount
            token.approve(dstList[i], 0);
        }
        emit TokenDestinationsRevoked();
    }

    /**
     * @notice Gets tokens currently available for release
     * @dev Considers the schedule, takes into account already released tokens and used amount
     * @return Amount of tokens ready to be released
     */
    function releasableAmount() public view override returns (uint256) {
        if (revocable == Revocability.Disabled) {
            return super.releasableAmount();
        }

        // -- Revocability enabled logic
        // This needs to deal with additional considerations for when tokens are used in the protocol

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
        // We consider the `usedAmount` in the protocol as part of the calculations
        // the beneficiary should not release funds that are used.
        uint256 releasable = availableAmount().sub(releasedAmount).sub(usedAmount);
        return MathUtils.min(currentBalance(), releasable);
    }

    /**
     * @notice Forward authorized contract calls to protocol contracts
     * @dev Fallback function can be called by the beneficiary only if function call is allowed
     */
    // solhint-disable-next-line no-complex-fallback
    fallback() external payable {
        // Only beneficiary can forward calls
        require(msg.sender == beneficiary, "Unauthorized caller");
        require(msg.value == 0, "ETH transfers not supported");

        // Function call validation
        address _target = manager.getAuthFunctionCallTarget(msg.sig);
        require(_target != address(0), "Unauthorized function");

        uint256 oldBalance = currentBalance();

        // Call function with data
        Address.functionCall(_target, msg.data);

        // Tracked used tokens in the protocol
        // We do this check after balances were updated by the forwarded call
        // Check is only enforced for revocable contracts to save some gas
        if (revocable == Revocability.Enabled) {
            // Track contract balance change
            uint256 newBalance = currentBalance();
            if (newBalance < oldBalance) {
                // Outflow
                uint256 diff = oldBalance.sub(newBalance);
                usedAmount = usedAmount.add(diff);
            } else {
                // Inflow: We can receive profits from the protocol, that could make usedAmount to
                // underflow. We set it to zero in that case.
                uint256 diff = newBalance.sub(oldBalance);
                usedAmount = (diff >= usedAmount) ? 0 : usedAmount.sub(diff);
            }
            require(usedAmount <= vestedAmount(), "Cannot use more tokens than vested amount");
        }
    }

    /**
     * @notice Receive function that always reverts.
     * @dev Only included to supress warnings, see https://github.com/ethereum/solidity/issues/10159
     */
    receive() external payable {
        revert("Bad call");
    }
}
