// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.30;

/**
 * @title TestProxy
 * @notice A simple proxy contract for testing upgradeable contracts
 */
contract TestProxy {
    address private immutable _implementation;
    address private immutable _admin;
    
    /**
     * @notice Constructor for the TestProxy contract
     * @param implementation_ Address of the implementation contract
     * @param admin_ Address of the admin
     * @param data Initialization data to be passed to the implementation
     */
    constructor(address implementation_, address admin_, bytes memory data) {
        _implementation = implementation_;
        _admin = admin_;
        
        // Call the implementation with the initialization data
        (bool success, ) = implementation_.delegatecall(data);
        require(success, "Initialization failed");
    }
    
    /**
     * @notice Fallback function that delegates all calls to the implementation contract
     */
    fallback() external payable {
        address implementation = _implementation;
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
    
    /**
     * @notice Receive function to accept ETH
     */
    receive() external payable {}
}
