pragma solidity ^0.7.6;

interface ITestRegistrar {
    function register(bytes32 label, address owner) external;
}
