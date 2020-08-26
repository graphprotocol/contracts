pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../governance/Governed.sol";

/**
 * @title GraphSignalToken contract
 * @dev This is the implementation of the Curation Signal ERC20 token (GST).
 * GST tokens are created for each subgraph deployment curated in the Curation contract.
 * The Curation contract is the owner of GST tokens and the only one allowed to mint or
 * burn them. GST tokens are transferrable and their holders can do any action allowed
 * in a standard ERC20 token implementation except for burning them.
 */
contract GraphSignalToken is ERC20, Governed {
    /**
     * @dev Graph Token Contract Constructor.
     * @param _symbol Token symbol
     * @param _owner Address of the contract issuing this token
     */
    constructor(string memory _symbol, address _owner) public ERC20("Graph Signal Token", _symbol) {
        Governed._initialize(_owner);
    }

    /**
     * @dev Mint new tokens.
     * @param _to Address to send the newly minted tokens
     * @param _amount Amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) public onlyGovernor {
        _mint(_to, _amount);
    }

    /**
     * @dev Burn tokens from an address.
     * @param _account Address from where tokens will be burned
     * @param _amount Amount of tokens to burn
     */
    function burnFrom(address _account, uint256 _amount) public onlyGovernor {
        _burn(_account, _amount);
    }
}
