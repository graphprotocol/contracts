// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.3;

import "@openzeppelin/contracts/utils/Address.sol";

import "./GraphProxyStorage.sol";

/**
 * @title Graph Proxy
 * @dev Graph Proxy contract used to delegate call implementation contracts and support upgrades.
 * This contract should NOT define storage as it is managed by GraphProxyStorage.
 * This contract implements a proxy that is upgradeable by an admin.
 * https://docs.openzeppelin.com/upgrades-plugins/1.x/proxies#transparent-proxies-and-function-clashes
 */
contract GraphProxy is GraphProxyStorage {
    /**
     * @dev Modifier used internally that will delegate the call to the implementation unless
     * the sender is the admin.
     */
    modifier ifAdmin() {
        if (msg.sender == _admin()) {
            _;
        } else {
            _fallback();
        }
    }

    /**
     * @dev Modifier used internally that will delegate the call to the implementation unless
     * the sender is the admin or pending implementation.
     */
    modifier ifAdminOrPendingImpl() {
        if (msg.sender == _admin() || msg.sender == _pendingImplementation()) {
            _;
        } else {
            _fallback();
        }
    }

    /**
     * @dev Contract constructor.
     * @param _impl Address of the initial implementation
     * @param _admin Address of the proxy admin
     */
    constructor(address _impl, address _admin) {
        assert(ADMIN_SLOT == bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1));
        assert(
            IMPLEMENTATION_SLOT == bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
        );
        assert(
            PENDING_IMPLEMENTATION_SLOT ==
                bytes32(uint256(keccak256("eip1967.proxy.pendingImplementation")) - 1)
        );

        _setAdmin(_admin);
        _setPendingImplementation(_impl);
    }

    /**
     * @dev Returns the current admin.
     *
     * NOTE: Only the admin and implementation can call this function.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using the
     * https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
     */
    function admin() external ifAdminOrPendingImpl returns (address) {
        return _admin();
    }

    /**
     * @dev Returns the current implementation.
     *
     * NOTE: Only the admin can call this function.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using the
     * https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`
     */
    function implementation() external ifAdminOrPendingImpl returns (address) {
        return _implementation();
    }

    /**
     * @dev Returns the current pending implementation.
     *
     * NOTE: Only the admin can call this function.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using the
     * https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0x9e5eddc59e0b171f57125ab86bee043d9128098c3a6b9adb4f2e86333c2f6f8c`
     */
    function pendingImplementation() external ifAdminOrPendingImpl returns (address) {
        return _pendingImplementation();
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * NOTE: Only the admin can call this function.
     */
    function setAdmin(address _newAdmin) external ifAdmin {
        require(_newAdmin != address(0), "Cannot change the admin of a proxy to the zero address");
        _setAdmin(_newAdmin);
    }

    /**
     * @dev Upgrades to a new implementation contract.
     * @param _newImplementation Address of implementation contract
     *
     * NOTE: Only the admin can call this function.
     */
    function upgradeTo(address _newImplementation) external ifAdmin {
        _setPendingImplementation(_newImplementation);
    }

    /**
     * @dev Admin function for new implementation to accept its role as implementation.
     */
    function acceptUpgrade() external ifAdminOrPendingImpl {
        _acceptUpgrade();
    }

    /**
     * @dev Admin function for new implementation to accept its role as implementation.
     */
    function acceptUpgradeAndCall(bytes calldata data) external ifAdminOrPendingImpl {
        _acceptUpgrade();
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = _implementation().delegatecall(data);
        require(success);
    }

    /**
     * @dev Admin function for new implementation to accept its role as implementation.
     */
    function _acceptUpgrade() internal {
        address _pendingImplementation = _pendingImplementation();
        require(Address.isContract(_pendingImplementation), "Implementation must be a contract");
        require(
            _pendingImplementation != address(0) && msg.sender == _pendingImplementation,
            "Caller must be the pending implementation"
        );

        _setImplementation(_pendingImplementation);
        _setPendingImplementation(address(0));
    }

    /**
     * @dev Delegates the current call to implementation.
     * This function does not return to its internal call site, it will return directly to the
     * external caller.
     */
    function _fallback() internal {
        require(msg.sender != _admin(), "Cannot fallback to proxy target");

        assembly {
            // (a) get free memory pointer
            let ptr := mload(0x40)

            // (b) get address of the implementation
            let impl := and(sload(IMPLEMENTATION_SLOT), 0xffffffffffffffffffffffffffffffffffffffff)

            // (1) copy incoming call data
            calldatacopy(ptr, 0, calldatasize())

            // (2) forward call to logic contract
            let result := delegatecall(gas(), impl, ptr, calldatasize(), 0, 0)
            let size := returndatasize()

            // (3) retrieve return data
            returndatacopy(ptr, 0, size)

            // (4) forward return data back to caller
            switch result
                case 0 {
                    revert(ptr, size)
                }
                default {
                    return(ptr, size)
                }
        }
    }

    /**
     * @dev Fallback function that delegates calls to implementation. Will run if no other
     * function in the contract matches the call data.
     */
    fallback() external payable {
        _fallback();
    }

    /**
     * @dev Fallback function that delegates calls to implementation. Will run if call data
     * is empty.
     */
    receive() external payable {
        _fallback();
    }
}
