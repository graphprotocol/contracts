// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

/**
 * @title MinimalProxyFactory: a factory contract for creating minimal proxies
 * @notice Adapted from https://github.com/OpenZeppelin/openzeppelin-sdk/blob/v2.5.0/packages/lib/contracts/upgradeability/ProxyFactory.sol
 * Based on https://eips.ethereum.org/EIPS/eip-1167
 */
contract MinimalProxyFactory {
    /// @dev Emitted when a new proxy is created
    event ProxyCreated(address indexed proxy);

    /**
     * @notice Gets the deterministic CREATE2 address for MinimalProxy with a particular implementation
     * @dev Uses address(this) as deployer to compute the address. Only for backwards compatibility.
     * @param _salt Bytes32 salt to use for CREATE2
     * @param _implementation Address of the proxy target implementation
     * @return Address of the counterfactual MinimalProxy
     */
    function getDeploymentAddress(bytes32 _salt, address _implementation) public view returns (address) {
        return getDeploymentAddress(_salt, _implementation, address(this));
    }

    /**
     * @notice Gets the deterministic CREATE2 address for MinimalProxy with a particular implementation
     * @param _salt Bytes32 salt to use for CREATE2
     * @param _implementation Address of the proxy target implementation
     * @param _deployer Address of the deployer that creates the contract
     * @return Address of the counterfactual MinimalProxy
     */
    function getDeploymentAddress(
        bytes32 _salt,
        address _implementation,
        address _deployer
    ) public pure returns (address) {
        return Create2.computeAddress(_salt, keccak256(_getContractCreationCode(_implementation)), _deployer);
    }

    /**
     * @dev Deploys a MinimalProxy with CREATE2
     * @param _salt Bytes32 salt to use for CREATE2
     * @param _implementation Address of the proxy target implementation
     * @param _data Bytes with the initializer call
     * @return Address of the deployed MinimalProxy
     */
    function _deployProxy2(bytes32 _salt, address _implementation, bytes memory _data) internal returns (address) {
        address proxyAddress = Create2.deploy(0, _salt, _getContractCreationCode(_implementation));

        emit ProxyCreated(proxyAddress);

        // Call function with data
        if (_data.length > 0) {
            Address.functionCall(proxyAddress, _data);
        }

        return proxyAddress;
    }

    /**
     * @dev Gets the MinimalProxy bytecode
     * @param _implementation Address of the proxy target implementation
     * @return MinimalProxy bytecode
     */
    function _getContractCreationCode(address _implementation) internal pure returns (bytes memory) {
        bytes10 creation = 0x3d602d80600a3d3981f3;
        bytes10 prefix = 0x363d3d373d3d3d363d73;
        bytes20 targetBytes = bytes20(_implementation);
        bytes15 suffix = 0x5af43d82803e903d91602b57fd5bf3;
        return abi.encodePacked(creation, prefix, targetBytes, suffix);
    }
}
