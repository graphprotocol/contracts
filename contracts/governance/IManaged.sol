pragma solidity ^0.6.12;

interface IManaged {
    event SetController(address controller);

    function setController(address _controller) external;
}
