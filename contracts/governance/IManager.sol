pragma solidity ^0.6.4;

interface IManager {
    event SetController(address controller);

    function setController(address _controller) external;
}
