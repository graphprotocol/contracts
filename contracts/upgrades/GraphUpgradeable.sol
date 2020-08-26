pragma solidity ^0.6.12;

import "./IGraphProxy.sol";
import "./GraphProxyStorage.sol";

/**
 * @title Graph Upgradeable
 * @dev This contract is intended to be inherited from upgradeable contracts.
 * This contract should NOT define storage as it is managed by GraphProxyStorage.
 */
contract GraphUpgradeable is GraphProxyStorage {
    /**
     * @dev Check if the caller is the proxy admin.
     */
    modifier onlyProxyAdmin(IGraphProxy _proxy) {
        require(msg.sender == _proxy.admin(), "Caller must be the proxy admin");
        _;
    }

    /**
     * @dev Check if the caller is the implementation.
     */
    modifier onlyImpl {
        require(msg.sender == _implementation(), "Caller must be the implementation");
        _;
    }

    /**
     * @dev Admin function for new implementation to accept its role as implementation.
     */
    function _acceptUpgrade(IGraphProxy _proxy) internal onlyProxyAdmin(_proxy) {
        _proxy.acceptUpgrade();
    }
}
