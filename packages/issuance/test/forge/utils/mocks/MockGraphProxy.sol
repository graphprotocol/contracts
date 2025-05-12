// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.30;

/**
 * @title MockGraphProxy
 * @notice A simplified version of GraphProxy for testing purposes
 */
contract MockGraphProxy {
    address public implementation;
    address public admin;
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 private constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @notice Constructor
     * @param _implementation Address of the implementation contract
     * @param _admin Address of the admin
     * @param _data Initialization data
     */
    constructor(address _implementation, address _admin, bytes memory _data) {
        _setAdmin(_admin);
        _setImplementation(_implementation);
        
        if (_data.length > 0) {
            (bool success, ) = _implementation.delegatecall(_data);
            require(success, "Initialization failed");
        }
    }

    /**
     * @notice Upgrade the implementation contract
     * @param _newImplementation Address of the new implementation contract
     */
    function upgradeTo(address _newImplementation) external {
        require(msg.sender == admin, "Only admin can upgrade");
        _setImplementation(_newImplementation);
    }

    /**
     * @notice Set the admin
     * @param _newAdmin Address of the new admin
     */
    function _setAdmin(address _newAdmin) private {
        assembly {
            sstore(ADMIN_SLOT, _newAdmin)
        }
    }

    /**
     * @notice Set the implementation
     * @param _newImplementation Address of the new implementation
     */
    function _setImplementation(address _newImplementation) private {
        implementation = _newImplementation;
        assembly {
            sstore(IMPLEMENTATION_SLOT, _newImplementation)
        }
    }

    /**
     * @notice Fallback function to delegate calls to the implementation contract
     */
    fallback() external payable {
        address _impl = implementation;
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), _impl, 0, calldatasize(), 0, 0)

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
