pragma solidity ^0.6.4;


contract IManager {
    event SetController(address controller);
    event ParameterUpdate(string param);

    function setController(address _controller) external;
}
