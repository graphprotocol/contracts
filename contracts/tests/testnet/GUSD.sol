pragma solidity ^0.6.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

import "../../governance/Governed.sol";

/**
 * @title Graph Testnet stablecoin contract
 * @dev This is the implementation of an ERC20 stablecoin used for experiments on testnet.
 */
contract GUSD is Governed, ERC20, ERC20Burnable {
    /**
     * @dev GUSD constructor.
     * @param _initialSupply Initial supply of GUSD
     */
    constructor(uint256 _initialSupply) public ERC20("Graph USD", "GUSD") {
        Governed._initialize(msg.sender);

        // The Governor has the initial supply of tokens
        _mint(msg.sender, _initialSupply);
    }

    /**
     * @dev Mint new tokens.
     * @param _to Address to send the newly minted tokens
     * @param _amount Amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external onlyGovernor {
        _mint(_to, _amount);
    }
}
