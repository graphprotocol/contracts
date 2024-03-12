// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.7.6;

interface IEthereumDIDRegistry {
    function identityOwner(address identity) external view returns (address);

    function setAttribute(address identity, bytes32 name, bytes calldata value, uint256 validity) external;
}
