pragma solidity ^0.6.12;

interface IController {
    event SetContractProxy(bytes32 id, address contractAddress);

    function setContractProxy(bytes32 _id, address _contractAddress) external;

    function updateController(bytes32 _id, address _controller) external;

    function getContractProxy(bytes32 _id) external view returns (address);
}
