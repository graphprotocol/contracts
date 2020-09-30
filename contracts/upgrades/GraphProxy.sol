pragma solidity ^0.6.12;

import "./GraphProxyStorage.sol";

/**
 * @title Graph Proxy
 * @dev Graph Proxy contract used to delegate call implementation contracts and support upgrades.
 * This contract should NOT define storage as it is managed by GraphProxyStorage.
 */
contract GraphProxy is GraphProxyStorage {
    /**
     * @dev Contract constructor.
     * @param _impl Address of the initial implementation
     */
    constructor(address _impl) public {
        assert(ADMIN_SLOT == bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1));
        assert(
            IMPLEMENTATION_SLOT == bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
        );
        assert(
            PENDING_IMPLEMENTATION_SLOT ==
                bytes32(uint256(keccak256("eip1967.proxy.pendingImplementation")) - 1)
        );

        _setAdmin(msg.sender);
        _setPendingImplementation(_impl);
    }

    /**
     * @return adm Get the current admin.
     */
    function admin() external view returns (address) {
        return _admin();
    }

    /**
     * @dev Sets the address of the proxy admin.
     * @param _newAdmin Address of the new proxy admin
     */
    function setAdmin(address _newAdmin) external onlyAdmin {
        require(_newAdmin != address(0), "Cannot change the admin of a proxy to the zero address");
        _setAdmin(_newAdmin);
    }

    /**
     * @return The address of the implementation.
     */
    function implementation() external view returns (address) {
        return _implementation();
    }

    /**
     * @return The address of the pending implementation.
     */
    function pendingImplementation() external view returns (address) {
        return _pendingimplementation();
    }

    /**
     * @dev Upgrades to a new implementation contract.
     * @param _newImplementation Address of implementation contract
     */
    function upgradeTo(address _newImplementation) public onlyAdmin {
        _setPendingImplementation(_newImplementation);
    }

    /**
     * @dev Admin function for new implementation to accept its role as implementation.
     */
    function acceptUpgrade() external {
        address _pendingImplementation = _pendingimplementation();
        require(
            _pendingImplementation != address(0) && msg.sender == _pendingImplementation,
            "Caller must be the pending implementation"
        );

        _setImplementation(_pendingImplementation);
        _setPendingImplementation(address(0));
    }

    /**
     * @dev Delegates execution to an implementation contract.
     * It returns to the external caller what the implementation returns
     * or forwards reverts.
     */
    fallback() external payable {
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
}
