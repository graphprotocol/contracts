// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;

/* solhint-disable gas-custom-errors */ // Cannot use custom errors with 0.7.6

/**
 * @title Graph Proxy Storage
 * @author Edge & Node
 * @notice Contract functions related to getting and setting proxy storage.
 * This contract does not actually define state variables managed by the compiler
 * but uses fixed slot locations.
 */
abstract contract GraphProxyStorage {
    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev Storage slot with the address of the pending implementation.
     * This is the keccak-256 hash of "eip1967.proxy.pendingImplementation" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant PENDING_IMPLEMENTATION_SLOT =
        0x9e5eddc59e0b171f57125ab86bee043d9128098c3a6b9adb4f2e86333c2f6f8c;

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @notice Emitted when pendingImplementation is changed.
     * @param oldPendingImplementation Address of the previous pending implementation
     * @param newPendingImplementation Address of the new pending implementation
     */
    event PendingImplementationUpdated(
        address indexed oldPendingImplementation,
        address indexed newPendingImplementation
    );

    /**
     * @notice Emitted when pendingImplementation is accepted,
     * which means contract implementation is updated.
     * @param oldImplementation Address of the previous implementation
     * @param newImplementation Address of the new implementation
     */
    event ImplementationUpdated(address indexed oldImplementation, address indexed newImplementation);

    /**
     * @notice Emitted when the admin account has changed.
     * @param oldAdmin Address of the previous admin
     * @param newAdmin Address of the new admin
     */
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    /**
     * @dev Modifier to check whether the `msg.sender` is the admin.
     */
    modifier onlyAdmin() {
        require(msg.sender == _getAdmin(), "Caller must be admin");
        _;
    }

    /**
     * @notice Returns the current admin address
     * @return adm The admin slot.
     */
    function _getAdmin() internal view returns (address adm) {
        bytes32 slot = ADMIN_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            adm := sload(slot)
        }
    }

    /**
     * @notice Sets the address of the proxy admin.
     * @param _newAdmin Address of the new proxy admin
     */
    function _setAdmin(address _newAdmin) internal {
        address oldAdmin = _getAdmin();
        bytes32 slot = ADMIN_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, _newAdmin)
        }

        emit AdminUpdated(oldAdmin, _newAdmin);
    }

    /**
     * @notice Returns the current implementation.
     * @return impl Address of the current implementation
     */
    function _getImplementation() internal view returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            impl := sload(slot)
        }
    }

    /**
     * @notice Returns the current pending implementation.
     * @return impl Address of the current pending implementation
     */
    function _getPendingImplementation() internal view returns (address impl) {
        bytes32 slot = PENDING_IMPLEMENTATION_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            impl := sload(slot)
        }
    }

    /**
     * @notice Sets the implementation address of the proxy.
     * @param _newImplementation Address of the new implementation
     */
    function _setImplementation(address _newImplementation) internal {
        address oldImplementation = _getImplementation();

        bytes32 slot = IMPLEMENTATION_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, _newImplementation)
        }

        emit ImplementationUpdated(oldImplementation, _newImplementation);
    }

    /**
     * @notice Sets the pending implementation address of the proxy.
     * @param _newImplementation Address of the new pending implementation
     */
    function _setPendingImplementation(address _newImplementation) internal {
        address oldPendingImplementation = _getPendingImplementation();

        bytes32 slot = PENDING_IMPLEMENTATION_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, _newImplementation)
        }

        emit PendingImplementationUpdated(oldPendingImplementation, _newImplementation);
    }
}
