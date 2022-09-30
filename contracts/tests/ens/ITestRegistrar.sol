pragma solidity ^0.8.16;

interface ITestRegistrar {
    function register(bytes32 label, address owner) external;
}
