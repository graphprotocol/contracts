pragma solidity ^0.6.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title GraphSignalToken contract
 * @dev This is the implementation of Curation Signal as ERC20 token.
 */
contract GraphSignalToken is ERC20 {
    address public owner;

    modifier onlyOwner {
        require(msg.sender == owner, "Caller must be owner");
        _;
    }

    /**
     * @dev Graph Token Contract Constructor.
     * @param _symbol Token symbol
     * @param _owner Address of the contract issuing this token
     */
    constructor(string memory _symbol, address _owner) public ERC20("Graph Signal Token", _symbol) {
        owner = _owner;
    }

    /**
     * @dev Mint new tokens.
     * @param _to Address to send the newly minted tokens
     * @param _amount Amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    function burn(uint256 amount) public onlyOwner {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) public onlyOwner {
        _burn(account, amount);
    }
}
