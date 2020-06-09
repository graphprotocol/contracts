pragma solidity ^0.6.4;

interface IEthereumDIDRegistry {
    function identityOwner(address identity) external view returns (address);
}
