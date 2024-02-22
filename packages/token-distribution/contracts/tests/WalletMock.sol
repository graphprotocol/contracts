// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title WalletMock: a mock wallet contract for testing purposes
 * @dev For testing only, DO NOT USE IN PRODUCTION.
 * This is used to test L1-L2 transfer tools and to create scenarios
 * where an invalid wallet calls the transfer tool, e.g. a wallet that has an invalid
 * manager, or a wallet that has not been initialized.
 */
contract WalletMock {
    /// Target contract for the fallback function (usually a transfer tool contract)
    address public immutable target;
    /// Address of the GRT (mock) token
    address public immutable token;
    /// Address of the wallet's manager
    address public immutable manager;
    /// Whether the wallet has been initialized
    bool public immutable isInitialized;
    /// Whether the beneficiary has accepted the lock
    bool public immutable isAccepted;

    /**
     * @notice WalletMock constructor
     * @dev This constructor sets all the state variables so that
     * specific test scenarios can be created just by deploying this contract.
     * @param _target Target contract for the fallback function
     * @param _token Address of the GRT (mock) token
     * @param _manager Address of the wallet's manager
     * @param _isInitialized Whether the wallet has been initialized
     * @param _isAccepted Whether the beneficiary has accepted the lock
     */
    constructor(address _target, address _token, address _manager, bool _isInitialized, bool _isAccepted) {
        target = _target;
        token = _token;
        manager = _manager;
        isInitialized = _isInitialized;
        isAccepted = _isAccepted;
    }

    /**
     * @notice Fallback function
     * @dev This function calls the target contract with the data sent to this contract.
     * This is used to test the L1-L2 transfer tool.
     */
    fallback() external payable {
        // Call function with data
        Address.functionCall(target, msg.data);
    }

    /**
     * @notice Receive function
     * @dev This function is added to avoid compiler warnings, but just reverts.
     */
    receive() external payable {
        revert("Invalid call");
    }
}
