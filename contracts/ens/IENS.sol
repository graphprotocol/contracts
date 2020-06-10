pragma solidity ^0.6.4;

// Needed for abi and typechain in the npm package
interface IENS {
    function owner(bytes32 node) external view returns (address);
}