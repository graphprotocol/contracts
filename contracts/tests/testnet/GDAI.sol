// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.3;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

import "../../governance/Governed.sol";

/**
 * @title Graph Testnet stablecoin contract
 * @dev This is the implementation of an ERC20 stablecoin used for experiments on testnet.
 */
contract GDAI is Governed, ERC20, ERC20Burnable {
    address public GSR;

    /**
     * @dev GDAI constructor.
     */
    constructor() ERC20("Graph DAI", "GDAI") {
        Governed._initialize(msg.sender);

        // The Governor is sent all tokens
        _mint(msg.sender, 100000000 ether); // 100,000,000 GDAI
    }

    /**
     * @dev Check if the caller is the governor.
     */
    modifier onlyGovernorOrGSR {
        require(msg.sender == governor || msg.sender == GSR, "Only Governor or GSR can call");
        _;
    }

    function setGSR(address _GSR) external onlyGovernor {
        GSR = _GSR;
    }

    /**
     * @dev Mint new tokens.
     * @param _to Address to send the newly minted tokens
     * @param _amount Amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external onlyGovernorOrGSR {
        _mint(_to, _amount);
    }
}
