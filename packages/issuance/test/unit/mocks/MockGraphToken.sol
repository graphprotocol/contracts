// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Minimal ERC20 token for testing. Mints initial supply to deployer.
contract MockGraphToken is ERC20 {
    constructor() ERC20("Graph Token", "GRT") {
        _mint(msg.sender, 1_000_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
