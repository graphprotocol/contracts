pragma solidity ^0.5.2;

// ----------------------------------------------------------------------------
// Mintable ERC Token Standard #20 Abstract Contract / Interface
// ----------------------------------------------------------------------------
contract MintableERC20Interface {
    /* MINTABLE ERC20 */
    /**
     * @dev Internal function that mints an amount of the token and assigns it to
     * an account. This encapsulates the modification of balances such that the
     * proper events are emitted.
     * @param account The account that will receive the created tokens.
     * @param value The amount that will be created.
     */
    function mint(address account, uint256 value) external;
}
