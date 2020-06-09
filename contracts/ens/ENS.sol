pragma solidity ^0.6.4;

interface ENS {
    function owner(bytes32 node) external view returns (address);
}