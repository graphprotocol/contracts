pragma solidity 0.6.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract DolphinCoin is ERC20("DolphinCoin", "DOC") {
    uint8 public constant DECIMALS = 18;
    uint256 public constant INITIAL_SUPPLY = 10_000 * (uint256(10) ** DECIMALS);

    /**
     * @dev Constructor that gives msg.sender all of existing tokens.
     */
    constructor() public {
        _setupDecimals(DECIMALS);
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
