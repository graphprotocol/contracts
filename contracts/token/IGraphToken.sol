pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGraphToken is IERC20 {
    function burn(uint256 amount) external;

    function mint(address _to, uint256 _amount) external;
}
