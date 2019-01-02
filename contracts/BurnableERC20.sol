pragma solidity ^0.5.2;

// ----------------------------------------------------------------------------
// Burnable ERC Token Standard #20 Abstract Contract / Interface
// ----------------------------------------------------------------------------
contract BurnableERC20Interface {
    /* BURNABLE ERC20 */
    // Triggered whenever burn(uint256 _value) is called
    // event Burn(address indexed _burner, uint256 _value);

    /**
     * @dev Internal function that burns an amount of the token of a given
     * account.
     * @param _account The account whose tokens will be burnt.
     * @param _value The amount that will be burnt.
     */
    function burn(address _account, uint256 _value) public;
}
