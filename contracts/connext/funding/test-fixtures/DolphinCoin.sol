pragma solidity 0.5.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract DolphinCoin is ERC20 {
    uint8 public constant DECIMALS = 18;
    uint256 public constant INITIAL_SUPPLY = 10000 * (10 ** uint256(DECIMALS));

    /**
     * @dev Constructor that gives msg.sender all of existing tokens.
     */
    constructor() public {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
