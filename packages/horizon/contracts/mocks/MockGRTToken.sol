// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";

contract MockGRTToken is ERC20, IGraphToken {
    constructor() ERC20("Graph Token", "GRT") {}

    function burn(uint256 tokens) external {}

    function burnFrom(address from, uint256 tokens) external {
        _burn(from, tokens);
    }

    // -- Mint Admin --

    function addMinter(address account) external {}

    function removeMinter(address account) external {}

    function renounceMinter() external {}

    // -- Permit --

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {}

    // -- Allowance --

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {}

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {}

    function isMinter(address account) external view returns (bool) {}

    function mint(address to, uint256 tokens) public {
        _mint(to, tokens);
    }
}
