pragma solidity ^0.6.4;

interface IController {
    event SetContractProxy(bytes32 id, address contractAddress);

    function setContractProxy(bytes32 _id, address _contractAddress) external;

    function updateController(bytes32 _id, address _controller) external;

    function getContractProxy(bytes32 _id) external view returns (address);

    function governor() external view returns (address);

    function paused() external view returns (bool);

    function recoveryPaused() external view returns (bool);
}
