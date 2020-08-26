pragma solidity ^0.6.12;

interface IEthereumDIDRegistry {
    function identityOwner(address identity) external view returns (address);
    function setAttribute(
        address identity,
        bytes32 name,
        bytes calldata value,
        uint256 validity
    ) external;
}
