// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@graphprotocol/contracts/contracts/token/IGraphToken.sol";

contract MockGRTToken is ERC20, IGraphToken {
    constructor() ERC20("Graph Token", "GRT") {}

    function burn(uint256 amount) external {}

    function burnFrom(address _from, uint256 amount) external {
        _burn(_from, amount);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // -- Mint Admin --

    function addMinter(address _account) external {}

    function removeMinter(address _account) external {}

    function renounceMinter() external {}

    function isMinter(address _account) external view returns (bool) {}

    // -- Permit --

    function permit(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {}

    // -- Allowance --

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {}
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {}
}