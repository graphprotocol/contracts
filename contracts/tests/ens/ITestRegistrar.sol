pragma solidity ^0.6.4;

interface ITestRegistrar {
    function register(bytes32 label, address owner) external;
}