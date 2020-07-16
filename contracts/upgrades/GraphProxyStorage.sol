pragma solidity ^0.6.4;

import "../governance/GovernedStorage.sol";

/**
 * @title Graph Proxy storage
 * @dev Storage for the Graph Proxy contract.
 */
contract GraphProxyStorage is GovernedStorage {
    /**
     * @dev Active implementation.
     */
    address public implementation;

    /**
     * @dev Pending implementation.
     */
    address public pendingImplementation;
}
