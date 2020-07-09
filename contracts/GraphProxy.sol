pragma solidity ^0.6.4;

import "./GraphProxyStorage.sol";
import "./Governed.sol";

/**
 * @title Graph Proxy
 * @dev Graph Proxy contract used to delegate call implementation contracts and support upgrades.
 */
contract GraphProxy is GraphProxyStorage, Governed {
    /**
     * @dev Emitted when pendingImplementation is changed.
     */
    event NewPendingImplementation(
        address oldPendingImplementation,
        address newPendingImplementation
    );

    /**
     * @dev Emitted when pendingImplementation is accepted,
     * which means contract implementation is updated.
     */
    event NewImplementation(address oldImplementation, address newImplementation);

    /**
     * @dev Upgrades to a new implementation contract.
     * @param _newImplementation Address of implementation contract
     */
    function upgradeTo(address _newImplementation) external onlyGovernor {
        address oldPendingImplementation = pendingImplementation;
        pendingImplementation = _newImplementation;

        emit NewPendingImplementation(oldPendingImplementation, pendingImplementation);
    }

    /**
     * @dev Admin function for new implementation to accept it's role as implementation
     */
    function acceptImplementation() external {
        require(
            pendingImplementation != address(0) && msg.sender == pendingImplementation,
            "Caller must be pending implementation"
        );

        address oldImplementation = implementation;
        address oldPendingImplementation = pendingImplementation;

        implementation = pendingImplementation;
        pendingImplementation = address(0);

        emit NewImplementation(oldImplementation, implementation);
        emit NewPendingImplementation(oldPendingImplementation, pendingImplementation);
    }

    /**
     * @dev Delegates execution to an implementation contract.
     * It returns to the external caller what the implementation returns
     * or forwards reverts.
     */
    fallback() external payable {
        assembly {
            let ptr := mload(0x40)

            // (1) copy incoming call data
            calldatacopy(ptr, 0, calldatasize())

            // (2) forward call to logic contract
            let result := delegatecall(gas(), implementation_slot, ptr, calldatasize(), 0, 0)
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
