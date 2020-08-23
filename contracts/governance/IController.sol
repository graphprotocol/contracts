pragma solidity ^0.6.4;

interface IController {
    event SetContract(bytes32 id, address contractAddress);

    function setContract(bytes32 _id, address _contractAddress) external;

    function updateController(bytes32 _id, address _controller) external;

    function getContractProxy(bytes32 _id) external view returns (address);
}
