pragma solidity ^0.7.3;

interface ITestRegistrar {
    function register(bytes32 label, address owner) external;
}
